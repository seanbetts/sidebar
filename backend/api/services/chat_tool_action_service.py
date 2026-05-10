"""Chat tool confirmation and undo action orchestration."""

from __future__ import annotations

from typing import Any
from uuid import UUID

from api.db.session import user_scoped_session
from api.services.agent.tools.mapper import ToolMapper
from api.services.agent.tools.skills_guard import skills_guard_service
from api.services.ai.tool_event_mapper import tool_side_effect_events
from api.services.ai.tool_result_normalizer import normalize_tool_result
from api.services.conversation_service import ConversationService


def attach_confirmation_metadata_to_tool_call(
    *,
    tool_calls_by_id: dict[str, dict[str, Any]],
    confirmation_data: dict[str, Any],
) -> None:
    """Attach pending confirmation metadata to the persisted tool-call snapshot."""
    tool_call_id = confirmation_data.get("tool_call_id")
    if not isinstance(tool_call_id, str) or not tool_call_id.strip():
        return
    existing = tool_calls_by_id.get(tool_call_id)
    if existing is None:
        return
    metadata_fields = {
        "confirmationId": confirmation_data.get("confirmation_id"),
        "confirmationSummary": confirmation_data.get("summary"),
        "confirmationGuardReason": confirmation_data.get("guard_reason"),
        "confirmationUndoSupported": confirmation_data.get("undo_supported"),
        "confirmationExpiresAt": confirmation_data.get("expires_at"),
    }
    for key, value in metadata_fields.items():
        if value is not None:
            existing[key] = value


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

    assistant_message: str | None = _decline_acknowledgement(pending.display_name)
    if pending.resolved_decision != "decline":
        assistant_message = None
    events = [
        skills_guard_service.build_confirmation_resolved_event(
            pending,
            assistant_message=assistant_message,
        )
    ]
    if pending.resolved_decision == "decline":
        _update_tool_action_message(
            user_id=user_id,
            conversation_id=pending.conversation_id,
            assistant_message_id=pending.assistant_message_id,
            tool_call_id=pending.tool_call_id,
            tool_status="cancelled",
            result={"success": False, "summary": "Cancelled"},
            append_content=assistant_message,
        )
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
            conversation_id=pending.conversation_id,
            assistant_message_id=pending.assistant_message_id,
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

    _update_tool_action_message(
        user_id=user_id,
        conversation_id=pending.conversation_id,
        assistant_message_id=pending.assistant_message_id,
        tool_call_id=pending.tool_call_id,
        tool_status=tool_result_event["status"],
        result=normalized_result,
    )

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
        undo = skills_guard_service.undo_tokens.get(undo_token)
        if undo and undo.conversation_id and undo.assistant_message_id:
            ConversationService.append_message_content(
                db,
                user_id,
                UUID(undo.conversation_id),
                undo.assistant_message_id,
                _undo_acknowledgement(undo.entity_type),
            )
    return {"success": True, "data": restored}


def _update_tool_action_message(
    *,
    user_id: str,
    conversation_id: str | None,
    assistant_message_id: str | None,
    tool_call_id: str,
    tool_status: str,
    result: dict[str, Any] | None = None,
    append_content: str | None = None,
) -> None:
    if not conversation_id or not assistant_message_id:
        return
    with user_scoped_session(user_id) as db:
        ConversationService.update_tool_action_message(
            db,
            user_id,
            UUID(conversation_id),
            assistant_message_id,
            tool_call_id=tool_call_id,
            tool_status=tool_status,
            result=result,
            append_content=append_content,
        )


def _decline_acknowledgement(display_name: str) -> str:
    noun = _tool_object_name(display_name)
    return f"Okay, I won't delete this {noun}."


def _undo_acknowledgement(entity_type: str) -> str:
    noun = entity_type.replace("_", " ")
    return f"Restored this {noun}."


def _tool_object_name(display_name: str) -> str:
    if display_name.startswith("Delete "):
        return display_name.removeprefix("Delete ").strip().lower() or "item"
    return "item"
