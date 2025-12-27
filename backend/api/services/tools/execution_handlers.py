"""Special-case tool execution handlers."""
from __future__ import annotations

from typing import Any, Dict


def handle_ui_theme(parameters: dict) -> Dict[str, Any]:
    theme = parameters.get("theme")
    if theme not in {"light", "dark"}:
        return {"success": False, "error": "Invalid theme"}
    return {"success": True, "data": {"theme": theme}}


def handle_prompt_preview(context: Dict[str, Any] | None) -> Dict[str, Any]:
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


def handle_memory_tool(context: Dict[str, Any] | None, parameters: dict) -> Dict[str, Any]:
    if not context:
        return {"success": False, "error": "Missing memory context"}
    db = context.get("db")
    user_id = context.get("user_id")
    if not db or not user_id:
        return {"success": False, "error": "Missing database or user context"}

    from api.services.memory_tool_handler import MemoryToolHandler

    return MemoryToolHandler.execute_command(db, user_id, parameters)
