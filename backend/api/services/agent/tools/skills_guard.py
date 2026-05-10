"""Confirmation and undo guards for assistant skill tools."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import uuid4

from sqlalchemy.orm import Session

from api.services.ai.chat_stream_sync_events import (
    build_tool_confirmation_requested,
    build_tool_confirmation_resolved,
    build_undo_available,
)


@dataclass(frozen=True)
class GuardedToolSpec:
    """Policy metadata for one guarded destructive tool."""

    entity_type: str
    id_parameter: str
    label: str
    undo_supported: bool


@dataclass
class PendingConfirmation:
    """Stored confirmation state for one pending destructive tool call."""

    confirmation_id: str
    user_id: str
    tool_call_id: str
    tool_name: str
    display_name: str
    parameters: dict[str, Any]
    summary: str
    undo_supported: bool
    expires_at: datetime
    skill_id: str | None = None
    icon_key: str | None = None
    conversation_id: str | None = None
    assistant_message_id: str | None = None
    resolved_decision: str | None = None
    resolved_at: datetime | None = None


@dataclass
class UndoToken:
    """Stored undo token state for a reversible destructive action."""

    token: str
    user_id: str
    display_name: str
    entity_type: str
    entity_id: str
    summary: str
    expires_at: datetime
    conversation_id: str | None = None
    assistant_message_id: str | None = None
    used_at: datetime | None = None


_PENDING_CONFIRMATIONS: dict[str, PendingConfirmation] = {}
_UNDO_TOKENS: dict[str, UndoToken] = {}


class SkillsGuardService:
    """Manage destructive tool confirmation gates and short-lived undo tokens."""

    confirmation_ttl = timedelta(minutes=5)
    undo_ttl = timedelta(minutes=5)

    guarded_tools: dict[str, GuardedToolSpec] = {
        "Delete Note": GuardedToolSpec("note", "note_id", "note", True),
        "Delete Note Folder": GuardedToolSpec(
            "note_folder", "path", "note folder", True
        ),
        "Delete Website": GuardedToolSpec("website", "website_id", "website", True),
        "Delete Task": GuardedToolSpec("task", "task_id", "task", True),
        "Delete Project": GuardedToolSpec("project", "project_id", "project", True),
        "Delete Group": GuardedToolSpec("group", "group_id", "group", True),
        "Delete File": GuardedToolSpec("file", "path", "file", False),
    }

    def __init__(
        self,
        *,
        now: Callable[[], datetime] | None = None,
        pending_confirmations: dict[str, PendingConfirmation] | None = None,
        undo_tokens: dict[str, UndoToken] | None = None,
    ) -> None:
        """Initialize the guard service with injectable stores for tests."""
        self._now = now or (lambda: datetime.now(UTC))
        self.pending_confirmations = (
            pending_confirmations
            if pending_confirmations is not None
            else _PENDING_CONFIRMATIONS
        )
        self.undo_tokens = undo_tokens if undo_tokens is not None else _UNDO_TOKENS

    @classmethod
    def requires_confirmation(cls, display_name: str) -> bool:
        """Return whether a display tool name requires user confirmation."""
        return display_name in cls.guarded_tools

    def create_confirmation_requested_event(
        self,
        *,
        user_id: str,
        tool_call_id: str,
        tool_name: str,
        display_name: str,
        parameters: dict[str, Any],
        skill_id: str | None = None,
        icon_key: str | None = None,
        conversation_id: str | None = None,
        assistant_message_id: str | None = None,
    ) -> dict[str, Any]:
        """Create and store a pending confirmation request event."""
        spec = self._spec(display_name)
        confirmation_id = str(uuid4())
        expires_at = self._now() + self.confirmation_ttl
        summary = self._summary(spec, parameters)
        pending = PendingConfirmation(
            confirmation_id=confirmation_id,
            user_id=user_id,
            tool_call_id=tool_call_id,
            tool_name=tool_name,
            display_name=display_name,
            parameters=dict(parameters),
            summary=summary,
            undo_supported=spec.undo_supported,
            expires_at=expires_at,
            skill_id=skill_id,
            icon_key=icon_key,
            conversation_id=conversation_id,
            assistant_message_id=assistant_message_id,
        )
        self.pending_confirmations[confirmation_id] = pending
        payload: dict[str, Any] = {
            "confirmation_id": confirmation_id,
            "tool_call_id": tool_call_id,
            "tool_name": display_name,
            "parameters": dict(parameters),
            "summary": summary,
            "guard_reason": "destructive_action",
            "undo_supported": spec.undo_supported,
            "expires_at": expires_at.isoformat(),
        }
        if skill_id:
            payload["skill_id"] = skill_id
        if icon_key:
            payload["icon_key"] = icon_key
        return build_tool_confirmation_requested(payload)

    def resolve_confirmation(
        self,
        confirmation_id: str,
        *,
        user_id: str,
        decision: str,
    ) -> PendingConfirmation:
        """Resolve a pending confirmation once for the owning user."""
        pending = self.pending_confirmations.get(confirmation_id)
        if pending is None:
            raise ValueError("Confirmation not found")
        if pending.user_id != user_id:
            raise ValueError("Confirmation not found")
        if pending.resolved_decision is not None:
            raise ValueError("Confirmation already resolved")
        now = self._now()
        if now > pending.expires_at:
            raise ValueError("Confirmation expired")
        normalized_decision = decision.strip().lower()
        if normalized_decision not in {"accept", "decline"}:
            raise ValueError("Decision must be accept or decline")
        pending.resolved_decision = normalized_decision
        pending.resolved_at = now
        return pending

    def build_confirmation_resolved_event(
        self,
        pending: PendingConfirmation,
        *,
        assistant_message: str | None = None,
    ) -> dict[str, Any]:
        """Build a stream event for a resolved confirmation."""
        if pending.resolved_decision is None or pending.resolved_at is None:
            raise ValueError("Confirmation has not been resolved")
        return build_tool_confirmation_resolved(
            {
                "confirmation_id": pending.confirmation_id,
                "tool_call_id": pending.tool_call_id,
                "decision": pending.resolved_decision,
                "resolved_at": pending.resolved_at.isoformat(),
                "assistant_message": assistant_message,
            }
        )

    def create_undo_available_event(
        self,
        *,
        user_id: str,
        display_name: str,
        parameters: dict[str, Any],
        result_data: dict[str, Any],
        conversation_id: str | None = None,
        assistant_message_id: str | None = None,
    ) -> dict[str, Any] | None:
        """Create an undo token event for a successful reversible deletion."""
        spec = self.guarded_tools.get(display_name)
        if spec is None or not spec.undo_supported:
            return None
        entity_id = self._entity_id(spec, parameters, result_data)
        if not entity_id:
            return None
        token = str(uuid4())
        expires_at = self._now() + self.undo_ttl
        summary = f"Undo {spec.label} deletion?"
        undo = UndoToken(
            token=token,
            user_id=user_id,
            display_name=display_name,
            entity_type=spec.entity_type,
            entity_id=entity_id,
            summary=summary,
            expires_at=expires_at,
            conversation_id=conversation_id,
            assistant_message_id=assistant_message_id,
        )
        self.undo_tokens[token] = undo
        return build_undo_available(
            {
                "undo_token": token,
                "summary": summary,
                "expires_at": expires_at.isoformat(),
                "entity_type": spec.entity_type,
                "entity_id": entity_id,
            }
        )

    def consume_undo_token(
        self,
        token: str,
        *,
        user_id: str,
        db: Session,
    ) -> dict[str, str]:
        """Consume one undo token and restore the matching soft-deleted entity."""
        undo = self.undo_tokens.get(token)
        if undo is None or undo.user_id != user_id:
            raise ValueError("Undo token not found")
        if undo.used_at is not None:
            raise ValueError("Undo token already used")
        now = self._now()
        if now > undo.expires_at:
            raise ValueError("Undo token expired")

        self._restore_undo(db, user_id, undo)
        undo.used_at = now
        return {"entity_type": undo.entity_type, "entity_id": undo.entity_id}

    def _spec(self, display_name: str) -> GuardedToolSpec:
        spec = self.guarded_tools.get(display_name)
        if spec is None:
            raise ValueError(f"Tool does not require confirmation: {display_name}")
        return spec

    def _summary(self, spec: GuardedToolSpec, parameters: dict[str, Any]) -> str:
        entity_id = str(parameters.get(spec.id_parameter) or "").strip()
        return f"Delete {spec.label} {entity_id}?"

    def _entity_id(
        self,
        spec: GuardedToolSpec,
        parameters: dict[str, Any],
        result_data: dict[str, Any],
    ) -> str | None:
        for key in (
            "id",
            "note_id",
            "website_id",
            "taskId",
            "task_id",
            "projectId",
            "project_id",
            "groupId",
            "group_id",
            spec.id_parameter,
        ):
            value = result_data.get(key) or parameters.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        return None

    def _restore_undo(self, db: Session, user_id: str, undo: UndoToken) -> None:
        if undo.entity_type == "note":
            from api.services.notes_service import NotesService

            NotesService.restore_note(db, user_id, undo.entity_id)
        elif undo.entity_type == "note_folder":
            from api.services.notes_workspace_service import NotesWorkspaceService

            NotesWorkspaceService.restore_folder(db, user_id, undo.entity_id)
        elif undo.entity_type == "website":
            from api.services.websites_service import WebsitesService

            WebsitesService.restore_website(db, user_id, undo.entity_id)
        elif undo.entity_type == "task":
            from api.services.task_service import TaskService

            TaskService.restore_task_series(db, user_id, undo.entity_id)
        elif undo.entity_type == "project":
            from api.services.task_service import TaskService

            TaskService.restore_task_project(db, user_id, undo.entity_id)
        elif undo.entity_type == "group":
            from api.services.task_service import TaskService

            TaskService.restore_task_group(db, user_id, undo.entity_id)
        else:
            raise ValueError("Undo is not supported for this action")


skills_guard_service = SkillsGuardService()
