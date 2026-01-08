"""Special-case tool execution handlers."""

from __future__ import annotations

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

    from api.services.prompt_context_service import PromptContextService

    system_prompt, first_message_prompt = PromptContextService.build_prompts(
        db=db,
        user_id=user_id,
        open_context=context.get("open_context"),
        attachments=context.get("attachments"),
        user_agent=context.get("user_agent"),
        current_location=context.get("current_location"),
        current_location_levels=context.get("current_location_levels"),
        current_weather=context.get("current_weather"),
    )
    return {
        "success": True,
        "data": {
            "system_prompt": system_prompt,
            "first_message_prompt": first_message_prompt,
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
