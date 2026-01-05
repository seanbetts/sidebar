"""Maps MCP tools to Claude tool definitions and handles execution."""
import time
import re
from typing import Dict, Any, List

from api.services.tools.definitions import get_tool_definitions
from api.services.tools.execution_handlers import (
    handle_memory_tool,
    handle_prompt_preview,
    handle_ui_theme,
)
from api.config import settings
from api.executors.skill_executor import SkillExecutor
from api.security.path_validator import PathValidator
from api.security.audit_logger import AuditLogger


SKILLS_REQUIRING_USER_ID = {
    "fs",
    "notes",
    "web-save",
    "audio-transcribe",
    "youtube-transcribe",
    "youtube-download",
    "web-crawler-policy",
    "docx",
    "pdf",
    "pptx",
    "xlsx",
}


class ToolMapper:
    """Maps MCP tools to Claude tool definitions."""

    def __init__(self):
        """Initialize tool registry and path validation."""
        self.executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
        self.path_validator = PathValidator(settings.workspace_base, settings.writable_paths)

        # Single source of truth for all tools
        self.tools = get_tool_definitions()
        self._build_tool_name_maps()

    def _build_tool_name_maps(self) -> None:
        """Build mappings between safe tool names and display names."""
        self.tool_name_map = {}
        self.tool_name_reverse = {}
        for display_name in self.tools.keys():
            safe_name = self._normalize_tool_name(display_name)
            base = safe_name
            suffix = 1
            while safe_name in self.tool_name_map and self.tool_name_map[safe_name] != display_name:
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

    @staticmethod
    def _normalize_result(result: Any) -> Dict[str, Any]:
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

            return {
                "success": success,
                "data": data,
                "error": error
            }

    @staticmethod
    def _inject_user_id(
        skill: str | None,
        parameters: Dict[str, Any],
        context: Dict[str, Any] | None,
    ) -> Dict[str, Any]:
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
    def _ensure_user_id_arg(skill: str | None, args: List[str], user_id: str | None) -> None:
        """Append --user-id when required and missing."""
        if not skill or skill not in SKILLS_REQUIRING_USER_ID:
            return
        if not user_id:
            raise ValueError(f"Skill '{skill}' requires user_id parameter")
        if "--user-id" not in args:
            args.extend(["--user-id", user_id])

        return {
            "success": True,
            "data": result,
            "error": None
        }

    def get_claude_tools(self, allowed_skills: List[str] | None = None) -> List[Dict[str, Any]]:
        """Convert tool configs to Claude tool schema."""
        return [
            {
                "name": self.tool_name_reverse.get(name, name),
                "description": config["description"],
                "input_schema": config["input_schema"]
            }
            for name, config in self.tools.items()
            if self._is_skill_enabled(config.get("skill"), allowed_skills)
        ]

    async def execute_tool(
        self,
        name: str,
        parameters: dict,
        allowed_skills: List[str] | None = None,
        context: Dict[str, Any] | None = None
    ) -> Dict[str, Any]:
        """Execute tool via skill executor."""
        start_time = time.time()

        try:
            # Get tool config
            display_name = self.get_tool_display_name(name)
            tool_config = self.tools.get(display_name)
            if not tool_config:
                return self._normalize_result({
                    "success": False,
                    "error": f"Unknown tool: {display_name}"
                })

            if not self._is_skill_enabled(tool_config.get("skill"), allowed_skills):
                return self._normalize_result({
                    "success": False,
                    "error": f"Skill disabled: {tool_config.get('skill')}"
                })

            # Special case: UI theme (no skill execution)
            if display_name == "Set UI Theme":
                result = handle_ui_theme(parameters)
                AuditLogger.log_tool_call(
                    tool_name=name,
                    parameters={"theme": parameters.get("theme")},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False),
                )

                return self._normalize_result(result)

            # Special case: prompt preview
            if display_name == "Generate Prompts":
                result = handle_prompt_preview(context)
                AuditLogger.log_tool_call(
                    tool_name=display_name,
                    parameters={},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False),
                )

                return self._normalize_result(result)

            # Special case: memory tool
            if display_name == "Memory Tool":
                result = handle_memory_tool(context, parameters)
                return self._normalize_result(result)

            # Validate paths if needed
            if tool_config.get("validate_write"):
                if "path" in parameters:
                    self.path_validator.validate_write_path(parameters["path"])
            elif tool_config.get("validate_read"):
                path_to_validate = parameters.get("path") or parameters.get("directory", ".")
                self.path_validator.validate_read_path(path_to_validate)

            skill = tool_config.get("skill")
            parameters = self._inject_user_id(skill, parameters, context)

            # Build arguments using the tool's build function
            args = tool_config["build_args"](parameters)
            self._ensure_user_id_arg(skill, args, parameters.get("user_id"))

            # Execute skill
            result = await self.executor.execute(
                tool_config["skill"],
                tool_config["script"],
                args,
                expect_json=tool_config.get("expect_json", True),
            )

            # Log execution (redact sensitive content)
            log_params = parameters.copy()
            if "content" in log_params and display_name == "Update Scratchpad":
                log_params["content"] = "<redacted>"
            if "content" in log_params and display_name in ["Create Note", "Update Note", "Write File"]:
                log_params.pop("content", None)

            AuditLogger.log_tool_call(
                tool_name=display_name,
                parameters=log_params,
                duration_ms=(time.time() - start_time) * 1000,
                success=result.get("success", False)
            )

            return self._normalize_result(result)

        except Exception as e:
            AuditLogger.log_tool_call(
                tool_name=name,
                parameters=parameters,
                duration_ms=(time.time() - start_time) * 1000,
                success=False,
                error=str(e)
            )
            return self._normalize_result({"success": False, "error": str(e)})

    @staticmethod
    def _is_skill_enabled(skill_name: str | None, allowed_skills: List[str] | None) -> bool:
        """Return True when a skill is enabled for execution."""
        if not skill_name:
            return True
        if allowed_skills is None:
            return True
        return skill_name in set(allowed_skills)
