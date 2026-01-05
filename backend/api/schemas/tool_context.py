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
    notes_context: str | None = None
    user_agent: str | None = None
    current_location: str | None = None
    current_location_levels: dict[str, Any] | str | None = None
    current_weather: dict[str, Any] | str | None = None
    current_timezone: str | None = None

    def to_dict(self) -> dict[str, Any]:
        """Convert the context to a legacy dict payload."""
        return {
            "db": self.db,
            "user_id": self.user_id,
            "open_context": self.open_context,
            "attachments": self.attachments,
            "conversation_id": str(self.conversation_id) if self.conversation_id else None,
            "user_message_id": str(self.user_message_id) if self.user_message_id else None,
            "assistant_message_id": str(self.assistant_message_id) if self.assistant_message_id else None,
            "notes_context": self.notes_context,
            "user_agent": self.user_agent,
            "current_location": self.current_location,
            "current_location_levels": self.current_location_levels,
            "current_weather": self.current_weather,
            "current_timezone": self.current_timezone,
        }
