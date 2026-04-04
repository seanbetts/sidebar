"""Typed tool execution context payloads."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
from uuid import UUID

from sqlalchemy.orm import Session


@dataclass
class ToolExecutionContext:
    """Context passed to tool execution."""

    db: Session
    user_id: str
    open_context: dict[str, Any] | None = None
    attachments: list[dict[str, Any]] = field(default_factory=list)
    conversation_id: UUID | None = None
    user_message_id: UUID | None = None
    assistant_message_id: UUID | None = None
    message_visibility: str | None = None
    notes_context: str | None = None
    user_agent: str | None = None
    app_version: str | None = None
    current_location: str | None = None
    current_location_levels: dict[str, Any] | str | None = None
    current_weather: dict[str, Any] | str | None = None
    current_timezone: str | None = None
    selected_skill_ids: list[str] = field(default_factory=list)
    executable_skill_ids: list[str] = field(default_factory=list)
    blocked_skill_summaries: list[dict[str, Any]] = field(default_factory=list)
    enabled_skill_ids: list[str] = field(default_factory=list)
    runtime_capabilities: list[dict[str, Any]] = field(default_factory=list)
    prompt_preview_payload: dict[str, Any] | None = None
    onboarding_state: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        """Convert the context to a legacy dict payload."""
        return {
            "db": self.db,
            "user_id": self.user_id,
            "open_context": self.open_context,
            "attachments": self.attachments,
            "conversation_id": str(self.conversation_id)
            if self.conversation_id
            else None,
            "user_message_id": str(self.user_message_id)
            if self.user_message_id
            else None,
            "assistant_message_id": str(self.assistant_message_id)
            if self.assistant_message_id
            else None,
            "message_visibility": self.message_visibility,
            "notes_context": self.notes_context,
            "user_agent": self.user_agent,
            "app_version": self.app_version,
            "current_location": self.current_location,
            "current_location_levels": self.current_location_levels,
            "current_weather": self.current_weather,
            "current_timezone": self.current_timezone,
            "selected_skill_ids": self.selected_skill_ids,
            "executable_skill_ids": self.executable_skill_ids,
            "blocked_skill_summaries": self.blocked_skill_summaries,
            "enabled_skill_ids": self.enabled_skill_ids,
            "runtime_capabilities": self.runtime_capabilities,
            "prompt_preview_payload": self.prompt_preview_payload,
            "onboarding_state": self.onboarding_state,
        }
