"""Chat tool confirmation and undo action orchestration."""

from __future__ import annotations

from typing import Any

from api.db.session import user_scoped_session
from api.services.agent.tools.mapper import ToolMapper
from api.services.agent.tools.skills_guard import skills_guard_service
from api.services.ai.tool_event_mapper import tool_side_effect_events
from api.services.ai.tool_result_normalizer import normalize_tool_result


async def resolve_tool_confirmation_action(
    confirmation_id: str,
    *,
    user_id: str,
    decision: str,
) -> dict[str, Any]:
    """Resolve a pending destructive tool confirmation and execute accepted tools."""
    pending = skills_guard_service.resolve_confirmation(
        confirmation_id,
        user_id=user_id,
        decision=decision,
    )

    assistant_message = (
        "The action was not run." if pending.resolved_decision == "decline" else None
    )
    events = [
        skills_guard_service.build_confirmation_resolved_event(
            pending,
            assistant_message=assistant_message,
        )
    ]
    if pending.resolved_decision == "decline":
        return {
            "confirmation_id": confirmation_id,
            "decision": pending.resolved_decision,
            "events": events,
        }

    tool_mapper = ToolMapper()
    result = await tool_mapper.execute_tool(
        pending.tool_name,
        pending.parameters,
        context={
            "user_id": user_id,
            "db_session_factory": lambda: user_scoped_session(user_id),
        },
    )
    normalized_result = normalize_tool_result(pending.display_name, result)
    events.extend(tool_side_effect_events(pending.display_name, normalized_result))
    result_data = normalized_result.get("data") or {}
    if isinstance(result_data, dict):
        undo_event = skills_guard_service.create_undo_available_event(
            user_id=user_id,
            display_name=pending.display_name,
            parameters=pending.parameters,
            result_data=result_data,
        )
        if undo_event is not None:
            events.append(undo_event)

    tool_result_event: dict[str, Any] = {
        "type": "tool_result",
        "id": pending.tool_call_id,
        "name": pending.display_name,
        "result": normalized_result,
        "status": "success" if normalized_result.get("success") else "error",
    }
    if pending.skill_id:
        tool_result_event["skill_id"] = pending.skill_id
    if pending.icon_key:
        tool_result_event["icon_key"] = pending.icon_key

    return {
        "confirmation_id": confirmation_id,
        "decision": pending.resolved_decision,
        "tool_result": tool_result_event,
        "events": events,
    }


def undo_tool_action_token(undo_token: str, *, user_id: str) -> dict[str, Any]:
    """Consume an undo token for a recent reversible destructive tool action."""
    with user_scoped_session(user_id) as db:
        restored = skills_guard_service.consume_undo_token(
            undo_token,
            user_id=user_id,
            db=db,
        )
    return {"success": True, "data": restored}
