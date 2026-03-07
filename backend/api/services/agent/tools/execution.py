"""Special-case tool execution handlers."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any


def handle_ui_theme(parameters: dict) -> dict[str, Any]:
    """Handle UI theme tool execution.

    Args:
        parameters: Tool parameters including theme.

    Returns:
        Tool result payload with success or error.
    """
    theme = parameters.get("theme")
    if theme not in {"light", "dark"}:
        return {"success": False, "error": "Invalid theme"}
    return {"success": True, "data": {"theme": theme}}


def handle_prompt_preview(context: dict[str, Any] | None) -> dict[str, Any]:
    """Handle prompt preview tool execution.

    Args:
        context: Tool execution context with db/user info.

    Returns:
        Tool result payload containing prompts.
    """
    if not context:
        return {"success": False, "error": "Missing prompt context"}
    db = context.get("db")
    user_id = context.get("user_id")
    if not db or not user_id:
        return {"success": False, "error": "Missing database or user context"}
    precomputed_payload = context.get("prompt_preview_payload")
    if isinstance(precomputed_payload, dict):
        return {"success": True, "data": precomputed_payload}

    from api.config import settings
    from api.services.agent.request_assembly_service import RequestAssemblyService
    from api.services.ai.gateway import AIProviderGateway
    from api.services.ai.policy import AIPolicyService
    from api.services.ai.registry import get_default_model
    from api.services.settings_service import SettingsService
    from api.services.user_settings_service import UserSettingsService

    settings_record = UserSettingsService.get_settings(db, user_id)
    allowed_skills = SettingsService.resolve_enabled_skills(
        settings_record,
        db=db,
        user_id=user_id,
    )
    policy = AIPolicyService.resolve_from_settings(settings_record)
    selection = AIPolicyService.select_provider("chat", policy)
    provider = selection.provider
    model = get_default_model(provider, "chat", settings)
    assembled_inputs = RequestAssemblyService.build_assembled_inputs(
        db=db,
        user_id=user_id,
        message="",
        conversation_id=(
            str(context.get("conversation_id"))
            if context.get("conversation_id") is not None
            else None
        ),
        conversation_messages=None,
        request_history=[],
        user_message_id=(
            str(context.get("user_message_id"))
            if context.get("user_message_id") is not None
            else None
        ),
        open_context=context.get("open_context") or {},
        attachments=context.get("attachments") or [],
        user_agent=context.get("user_agent"),
        current_location=context.get("current_location"),
        current_location_levels=context.get("current_location_levels"),
        current_weather=context.get("current_weather"),
        current_timezone=context.get("current_timezone"),
        now=datetime.now(UTC),
    )
    ai_gateway = AIProviderGateway(settings)
    prepared_request = RequestAssemblyService.build_prepared_request(
        provider=provider,
        model=model,
        assembled_inputs=assembled_inputs,
        allowed_skills=allowed_skills,
        tool_definition_resolver=ai_gateway.get_chat_tool_definitions,
    )
    prompt_bundle = assembled_inputs.prompt_bundle
    return {
        "success": True,
        "data": {
            "system_prompt": prompt_bundle["system_prompt"]["text"],
            "first_message_prompt": prompt_bundle["first_message_prompt"]["text"],
            "system_prompt_sections": prompt_bundle["system_prompt"]["sections"],
            "first_message_prompt_sections": prompt_bundle["first_message_prompt"][
                "sections"
            ],
            "prompt_report": prompt_bundle["report"],
            "request_budget_report": prepared_request.budget_report.__dict__,
            "workspace_context_menu_actions": [
                "copy_markdown",
                "share_text",
                "download",
            ],
        },
    }


def handle_memory_tool(
    context: dict[str, Any] | None, parameters: dict
) -> dict[str, Any]:
    """Handle memory tool execution.

    Args:
        context: Tool execution context with db/user info.
        parameters: Memory tool parameters.

    Returns:
        Tool result payload from MemoryToolHandler.
    """
    if not context:
        return {"success": False, "error": "Missing memory context"}
    db = context.get("db")
    user_id = context.get("user_id")
    if not db or not user_id:
        return {"success": False, "error": "Missing database or user context"}

    from api.services.memory_tool_handler import MemoryToolHandler

    return MemoryToolHandler.execute_command(db, user_id, parameters)


def handle_other_preferences(parameters: dict) -> dict[str, Any]:
    """Validate and normalize local Other preferences payload."""
    weather_unit = parameters.get("weather_unit")
    biometric_unlock_enabled = parameters.get("biometric_unlock_enabled")

    if weather_unit not in {None, "celsius", "fahrenheit"}:
        return {"success": False, "error": "Invalid weather_unit"}
    if biometric_unlock_enabled is not None and not isinstance(
        biometric_unlock_enabled, bool
    ):
        return {"success": False, "error": "Invalid biometric_unlock_enabled"}

    result_data: dict[str, Any] = {}
    if weather_unit is not None:
        result_data["weather_unit"] = weather_unit
    if biometric_unlock_enabled is not None:
        result_data["biometric_unlock_enabled"] = biometric_unlock_enabled

    if not result_data:
        return {
            "success": False,
            "error": (
                "At least one preference is required: "
                "weather_unit or biometric_unlock_enabled"
            ),
        }

    return {"success": True, "data": result_data}
