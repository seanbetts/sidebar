"""Maps MCP tools to Claude tool definitions and handles execution."""

import re
import time
from datetime import UTC, datetime
from typing import Any

from api.config import settings
from api.metrics import tool_execution_duration_seconds, tool_executions_total
from api.security.audit_logger import AuditLogger
from api.security.path_validator import PathValidator
from api.services.agent.skills.executor import SkillExecutor
from api.services.agent.tools.execution import (
    handle_memory_tool,
    handle_other_preferences,
    handle_prompt_preview,
    handle_ui_theme,
)
from api.services.agent.tools.registry import get_tool_definitions
from api.services.ai.gateway import AIProviderGateway
from api.services.onboarding_service import OnboardingService
from api.services.tools.skill_metadata import canonicalize_skill_id
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.user_settings_service import UserSettingsService

SKILLS_REQUIRING_USER_ID = {
    "conversations",
    "assistant-identity",
    "assistant-soul",
    "product-feedback",
    "settings-profile-user",
    "files",
    "notes",
    "tasks",
    "web-save",
    "audio-transcribe",
    "youtube-transcribe",
    "youtube-download",
    "web-crawler-policy",
}

TRANSCRIPTION_TOOL_NAMES = {"Transcribe Audio", "Transcribe YouTube"}
FIRST_OUTCOME_TOOL_NAMES = {
    "Add Website",
    "Create Note",
    "Create Task",
    "Save Website",
    "Transcribe Audio",
    "Transcribe YouTube",
    "Write File",
}
SKILL_CONTEXT_FIELDS: dict[str, tuple[str, ...]] = {
    "product-feedback": (
        "user_agent",
        "conversation_id",
        "user_message_id",
        "assistant_message_id",
    )
}


class ToolMapper:
    """Maps MCP tools to Claude tool definitions."""

    def __init__(self):
        """Initialize tool registry and path validation."""
        self.executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
        self.ai_gateway = AIProviderGateway(settings)
        self.path_validator = PathValidator(
            settings.workspace_base, settings.writable_paths
        )

        # Single source of truth for all tools
        self.tools = get_tool_definitions()
        self._build_tool_name_maps()

    def _build_tool_name_maps(self) -> None:
        """Build mappings between safe tool names and display names."""
        self.tool_name_map: dict[str, str] = {}
        self.tool_name_reverse: dict[str, str] = {}
        for display_name in self.tools:
            safe_name = self._normalize_tool_name(display_name)
            base = safe_name
            suffix = 1
            while (
                safe_name in self.tool_name_map
                and self.tool_name_map[safe_name] != display_name
            ):
                suffix += 1
                safe_name = f"{base}_{suffix}"
                if len(safe_name) > 128:
                    safe_name = safe_name[:128]
            self.tool_name_map[safe_name] = display_name
            self.tool_name_reverse[display_name] = safe_name

    @staticmethod
    def _normalize_tool_name(name: str) -> str:
        """Normalize a display name into a safe tool name."""
        safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", name).strip("_")
        if not safe:
            safe = "tool"
        return safe[:128]

    def get_tool_display_name(self, tool_name: str) -> str:
        """Resolve a tool name to its display name."""
        return self.tool_name_map.get(tool_name, tool_name)

    def get_tool_skill_id(self, tool_name: str) -> str | None:
        """Resolve canonical skill ID for a tool name."""
        display_name = self.get_tool_display_name(tool_name)
        tool_config = self.tools.get(display_name)
        skill_id = tool_config.get("skill") if tool_config else None
        if not isinstance(skill_id, str) or not skill_id.strip():
            return None
        return canonicalize_skill_id(skill_id.strip())

    def get_tool_icon_key(self, tool_name: str) -> str | None:
        """Resolve icon key for a tool name."""
        return self.get_tool_skill_id(tool_name)

    @staticmethod
    def _normalize_result(result: Any) -> dict[str, Any]:
        """Normalize execution results into a standard payload."""
        if isinstance(result, dict):
            success = bool(result.get("success", False))
            data = result.get("data")
            error = result.get("error")

            if success and data is None:
                data = {
                    key: value
                    for key, value in result.items()
                    if key not in {"success", "error"}
                }

            if not success and not error:
                error = "Unknown error"

            return {"success": success, "data": data, "error": error}
        return {"success": False, "data": None, "error": "Invalid result payload"}

    @staticmethod
    def _inject_user_id(
        skill: str | None,
        parameters: dict[str, Any],
        context: dict[str, Any] | None,
    ) -> dict[str, Any]:
        """Ensure user_id is present for skills that require it."""
        if not skill or skill not in SKILLS_REQUIRING_USER_ID:
            return parameters
        user_id = context.get("user_id") if context else None
        if not user_id:
            raise ValueError(f"Skill '{skill}' requires user_id in context")
        if parameters.get("user_id") == user_id:
            return parameters
        return {**parameters, "user_id": user_id}

    @staticmethod
    def _inject_skill_context(
        skill: str | None,
        parameters: dict[str, Any],
        context: dict[str, Any] | None,
    ) -> dict[str, Any]:
        """Inject selected request context fields for specific skills."""
        if not skill or not context:
            return parameters

        fields = SKILL_CONTEXT_FIELDS.get(skill)
        if not fields:
            return parameters

        enriched = dict(parameters)
        for field_name in fields:
            if enriched.get(field_name) is not None:
                continue
            context_value = context.get(field_name)
            if context_value is None:
                continue
            if isinstance(context_value, str):
                normalized_value = context_value.strip()
            else:
                normalized_value = str(context_value).strip()
            if normalized_value:
                enriched[field_name] = normalized_value
        return enriched

    @staticmethod
    def _ensure_user_id_arg(
        skill: str | None, args: list[str], user_id: str | None
    ) -> None:
        """Append --user-id when required and missing."""
        if not skill or skill not in SKILLS_REQUIRING_USER_ID:
            return
        if not user_id:
            raise ValueError(f"Skill '{skill}' requires user_id parameter")
        if "--user-id" not in args:
            args.extend(["--user-id", user_id])

    @staticmethod
    def _settings_record_from_context(context: dict[str, Any] | None):
        """Fetch the user settings record from tool execution context."""
        if not context:
            return None
        db = context.get("db")
        user_id = context.get("user_id")
        if db is None or not user_id:
            return None
        return UserSettingsService.get_settings(db, str(user_id))

    @staticmethod
    def _provider_key_lookup_from_context(
        context: dict[str, Any] | None,
    ):
        """Build a BYOK provider key lookup callback from tool context."""
        if not context:
            return None
        db = context.get("db")
        user_id = context.get("user_id")
        if db is None or not user_id:
            return None

        def _lookup(provider):
            return UserAIProviderKeyService.get_active_key(db, str(user_id), provider)

        return _lookup

    @staticmethod
    def _should_mark_first_outcome_completed(
        display_name: str,
        context: dict[str, Any] | None,
    ) -> bool:
        """Return whether a successful tool result should complete the first outcome."""
        if display_name not in FIRST_OUTCOME_TOOL_NAMES or not context:
            return False

        onboarding_state = context.get("onboarding_state")
        if not isinstance(onboarding_state, dict):
            return False
        if onboarding_state.get("is_onboarding_complete") is True:
            return False

        milestones = onboarding_state.get("milestones")
        return not (
            isinstance(milestones, dict) and milestones.get("first_outcome_completed")
        )

    @staticmethod
    def _apply_first_outcome_completed_milestone(
        display_name: str,
        normalized: dict[str, Any],
        context: dict[str, Any] | None,
    ) -> dict[str, Any]:
        """Persist and annotate the first completed outcome milestone."""
        if not normalized.get("success"):
            return normalized
        if not ToolMapper._should_mark_first_outcome_completed(display_name, context):
            return normalized

        if context is None:
            return normalized

        db = context.get("db")
        user_id = context.get("user_id")
        if db is None or not user_id:
            return normalized

        timestamp = datetime.now(UTC).isoformat()
        updated_state = OnboardingService.update_onboarding_state(
            db,
            str(user_id),
            {"milestones": {"first_outcome_completed": timestamp}},
        )

        result_data = normalized.get("data")
        if not isinstance(result_data, dict):
            result_data = {}
        result_data = {
            **result_data,
            "onboarding_milestone": "first_outcome_completed",
            "onboarding_state": updated_state,
        }
        normalized["data"] = result_data

        if isinstance(context.get("onboarding_state"), dict):
            context["onboarding_state"] = updated_state

        return normalized

    def get_claude_tools(
        self, allowed_skills: list[str] | None = None
    ) -> list[dict[str, Any]]:
        """Convert tool configs to Claude tool schema."""
        return [
            {
                "name": self.tool_name_reverse.get(name, name),
                "description": config["description"],
                "input_schema": config["input_schema"],
            }
            for name, config in self.tools.items()
            if self._is_skill_enabled(config.get("skill"), allowed_skills)
        ]

    def get_skill_ids_for_tool_definitions(
        self,
        tool_definitions: list[dict[str, Any]] | None,
    ) -> list[str]:
        """Resolve the executable skill subset implied by tool definitions."""
        skill_ids: list[str] = []
        for tool_definition in tool_definitions or []:
            tool_name = tool_definition.get("name")
            if not isinstance(tool_name, str) or not tool_name.strip():
                continue
            skill_id = self.get_tool_skill_id(tool_name)
            if skill_id and skill_id not in skill_ids:
                skill_ids.append(skill_id)
        return skill_ids

    async def execute_tool(
        self,
        name: str,
        parameters: dict,
        allowed_skills: list[str] | None = None,
        context: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Execute tool via skill executor."""
        start_time = time.time()
        tool_skill = None

        try:
            # Get tool config
            display_name = self.get_tool_display_name(name)
            tool_config = self.tools.get(display_name)
            if not tool_config:
                return self._normalize_result(
                    {"success": False, "error": f"Unknown tool: {display_name}"}
                )

            if not self._is_skill_enabled(tool_config.get("skill"), allowed_skills):
                return self._normalize_result(
                    {
                        "success": False,
                        "error": f"Skill disabled: {tool_config.get('skill')}",
                    }
                )
            tool_skill = tool_config.get("skill") or display_name

            # Special case: UI theme (no skill execution)
            if display_name == "Set UI Theme":
                result = handle_ui_theme(parameters)
                AuditLogger.log_tool_call(
                    tool_name=name,
                    parameters={"theme": parameters.get("theme")},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False),
                )

                normalized = self._normalize_result(result)
                status = "success" if normalized.get("success") else "error"
                tool_executions_total.labels(tool_skill, status).inc()
                tool_execution_duration_seconds.labels(tool_skill).observe(
                    time.time() - start_time
                )
                return normalized

            # Special case: prompt preview
            if display_name == "Generate Prompts":
                result = handle_prompt_preview(context)
                AuditLogger.log_tool_call(
                    tool_name=display_name,
                    parameters={},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False),
                )

                normalized = self._normalize_result(result)
                status = "success" if normalized.get("success") else "error"
                tool_executions_total.labels(tool_skill, status).inc()
                tool_execution_duration_seconds.labels(tool_skill).observe(
                    time.time() - start_time
                )
                return normalized

            # Special case: memory tool
            if display_name == "Memory Tool":
                result = handle_memory_tool(context, parameters)
                normalized = self._normalize_result(result)
                status = "success" if normalized.get("success") else "error"
                tool_executions_total.labels(tool_skill, status).inc()
                tool_execution_duration_seconds.labels(tool_skill).observe(
                    time.time() - start_time
                )
                return normalized

            # Special case: local other preferences
            if display_name == "Set Other Preferences":
                result = handle_other_preferences(parameters)
                AuditLogger.log_tool_call(
                    tool_name=display_name,
                    parameters={
                        "weather_unit": parameters.get("weather_unit"),
                        "biometric_unlock_enabled": parameters.get(
                            "biometric_unlock_enabled"
                        ),
                    },
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False),
                )

                normalized = self._normalize_result(result)
                status = "success" if normalized.get("success") else "error"
                tool_executions_total.labels(tool_skill, status).inc()
                tool_execution_duration_seconds.labels(tool_skill).observe(
                    time.time() - start_time
                )
                return normalized

            # Special case: Get Skill Inventory (internal tool)
            if display_name == "Get Skill Inventory":
                result = self._execute_get_skill_inventory(parameters, context)
                normalized = self._normalize_result(result)
                status = "success" if normalized.get("success") else "error"
                tool_executions_total.labels(tool_skill, status).inc()
                tool_execution_duration_seconds.labels(tool_skill).observe(
                    time.time() - start_time
                )
                return normalized

            # Special case: Search Product Knowledge (internal tool)
            if display_name == "Search Product Knowledge":
                result = self._execute_search_product_knowledge(parameters)
                normalized = self._normalize_result(result)
                status = "success" if normalized.get("success") else "error"
                tool_executions_total.labels(tool_skill, status).inc()
                tool_execution_duration_seconds.labels(tool_skill).observe(
                    time.time() - start_time
                )
                return normalized

            # Validate paths if needed
            if tool_config.get("validate_write"):
                if "path" in parameters:
                    self.path_validator.validate_write_path(parameters["path"])
            elif tool_config.get("validate_read"):
                path_to_validate = parameters.get("path") or parameters.get(
                    "directory", "."
                )
                self.path_validator.validate_read_path(path_to_validate)

            skill = tool_config.get("skill")
            parameters = self._inject_user_id(skill, parameters, context)
            parameters = self._inject_skill_context(skill, parameters, context)
            env_overrides: dict[str, str] | None = None

            if display_name in TRANSCRIPTION_TOOL_NAMES:
                settings_record = self._settings_record_from_context(context)
                provider_key_lookup = self._provider_key_lookup_from_context(context)
                resolution = self.ai_gateway.resolve_transcription(
                    settings_record=settings_record,
                    requested_model=parameters.get("model"),
                    provider_key_lookup=provider_key_lookup,
                )
                parameters = {
                    **parameters,
                    "model": resolution.model,
                }
                env_overrides = {"OPENAI_API_KEY": resolution.api_key}

            # Build arguments using the tool's build function
            args = tool_config["build_args"](parameters)
            self._ensure_user_id_arg(skill, args, parameters.get("user_id"))

            # Execute skill
            result = await self.executor.execute(
                tool_config["skill"],
                tool_config["script"],
                args,
                expect_json=tool_config.get("expect_json", True),
                env_overrides=env_overrides,
            )

            # Log execution (redact sensitive content)
            log_params = parameters.copy()
            if "content" in log_params and display_name == "Update Scratchpad":
                log_params["content"] = "<redacted>"
            if "content" in log_params and display_name in [
                "Create Note",
                "Write File",
            ]:
                log_params.pop("content", None)

            normalized = self._normalize_result(result)
            normalized = self._apply_first_outcome_completed_milestone(
                display_name,
                normalized,
                context,
            )
            if normalized.get("success"):
                AuditLogger.log_tool_call(
                    tool_name=display_name,
                    parameters=log_params,
                    duration_ms=(time.time() - start_time) * 1000,
                    success=True,
                )
            status = "success" if normalized.get("success") else "error"
            tool_executions_total.labels(tool_skill, status).inc()
            tool_execution_duration_seconds.labels(tool_skill).observe(
                time.time() - start_time
            )
            return normalized

        except Exception as e:
            AuditLogger.log_tool_call(
                tool_name=name,
                parameters=parameters,
                duration_ms=(time.time() - start_time) * 1000,
                success=False,
                error=str(e),
            )
            tool_skill = tool_skill or name
            tool_executions_total.labels(tool_skill, "error").inc()
            tool_execution_duration_seconds.labels(tool_skill).observe(
                time.time() - start_time
            )
            return self._normalize_result({"success": False, "error": str(e)})

    @staticmethod
    def _execute_get_skill_inventory(
        parameters: dict[str, Any],
        context: dict[str, Any] | None,
    ) -> dict[str, Any]:
        """Handle Get Skill Inventory tool execution."""
        from api.services.tools.skill_metadata import (
            EXPOSED_SKILLS,
            SKILL_DISPLAY,
            get_skill_tier,
        )

        filter_status = parameters.get("filter", "all")
        enabled_skill_ids: list[str] = []
        runtime_capabilities: list[dict[str, Any]] = []
        if context:
            enabled_skill_ids = context.get("enabled_skill_ids") or []
            runtime_capabilities = context.get("runtime_capabilities") or []

        enabled_set = set(enabled_skill_ids)
        runtime_by_id = {str(c.get("skill_id")): c for c in runtime_capabilities}

        skills = []
        for skill_id in sorted(EXPOSED_SKILLS):
            display = SKILL_DISPLAY.get(skill_id, {})
            runtime = runtime_by_id.get(skill_id, {})
            status = str(runtime.get("availability_status", "unknown"))
            enabled = skill_id in enabled_set

            if filter_status == "enabled" and not enabled:
                continue
            if filter_status == "disabled" and enabled:
                continue
            if filter_status == "blocked" and status != "blocked":
                continue

            skills.append(
                {
                    "skill_id": skill_id,
                    "name": display.get("name", skill_id),
                    "description": display.get("description", ""),
                    "tier": get_skill_tier(skill_id),
                    "enabled": enabled,
                    "availability_status": status,
                    "availability_reason": runtime.get("availability_reason"),
                    "availability_remediation": runtime.get("availability_remediation"),
                }
            )

        return {"success": True, "data": {"skills": skills}}

    @staticmethod
    def _execute_search_product_knowledge(
        parameters: dict[str, Any],
    ) -> dict[str, Any]:
        """Handle Search Product Knowledge tool execution."""
        from api.services.knowledge.provider import get_docs_indexer

        query = parameters.get("query", "")
        if not query:
            return {"success": False, "error": "query is required"}

        try:
            indexer = get_docs_indexer()
        except RuntimeError:
            return {"success": False, "error": "Product knowledge not available"}

        results = indexer.search(query, max_results=5)
        formatted = []
        for doc in results:
            sections_text = "\n\n".join(
                f"### {s['heading']}\n{s['content']}" for s in doc.get("sections", [])
            )
            formatted.append(
                {
                    "title": doc["title"],
                    "summary": doc["summary"],
                    "path": doc["path"],
                    "content": sections_text,
                }
            )

        return {"success": True, "data": {"results": formatted}}

    @staticmethod
    def _is_skill_enabled(
        skill_name: str | None, allowed_skills: list[str] | None
    ) -> bool:
        """Return True when a skill is enabled for execution."""
        if not skill_name:
            return True
        if allowed_skills is None:
            return True
        normalized_allowed = {
            canonicalize_skill_id(skill_id)
            for skill_id in allowed_skills
            if isinstance(skill_id, str)
        }
        return canonicalize_skill_id(skill_name) in normalized_allowed
