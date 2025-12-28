"""Prompt context assembly for chat and tools."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from api.models.conversation import Conversation
from api.models.note import Note
from api.models.website import Website
from api.prompts import (
    build_first_message_prompt,
    build_system_prompt,
    build_recent_activity_block,
    build_open_context_block,
    detect_operating_system,
    resolve_template,
    CONTEXT_GUIDANCE_TEMPLATE,
)
from api.services.user_settings_service import UserSettingsService


class PromptContextService:
    """Build prompt context blocks from DB and open UI state."""

    MAX_SYSTEM_PROMPT_CHARS = 40000
    MAX_FIRST_MESSAGE_CHARS = 8000

    @staticmethod
    def build_prompts(
        db: Session,
        user_id: str,
        open_context: dict[str, Any] | None,
        user_agent: str | None,
        current_location: str | None = None,
        current_location_levels: dict[str, Any] | str | None = None,
        current_weather: dict[str, Any] | str | None = None,
        now: datetime | None = None,
    ) -> tuple[str, str]:
        """Build system and first-message prompts.

        Args:
            db: Database session.
            user_id: Current user ID.
            open_context: Open note/website context payload.
            user_agent: User agent string.
            current_location: Current location label.
            current_location_levels: Structured location levels.
            current_weather: Weather payload.
            now: Optional timestamp override.

        Returns:
            Tuple of (system_prompt, first_message_prompt).
        """
        timestamp = now or datetime.now(timezone.utc)
        settings_record = UserSettingsService.get_settings(db, user_id)
        location_fallback = (
            settings_record.location if settings_record and settings_record.location else "Unknown"
        )
        resolved_location = current_location or "Current location not available"
        operating_system = detect_operating_system(user_agent)

        system_prompt = build_system_prompt(
            settings_record,
            resolved_location,
            current_location_levels,
            current_weather,
            timestamp,
        )
        context_guidance = resolve_template(
            CONTEXT_GUIDANCE_TEMPLATE,
            {"name": settings_record.name.strip() if settings_record and settings_record.name else "the user"},
        )
        open_note = open_context.get("note") if isinstance(open_context, dict) else None
        open_website = open_context.get("website") if isinstance(open_context, dict) else None
        open_block = build_open_context_block(open_note, open_website)

        note_items, website_items, conversation_items = PromptContextService._get_recent_activity(
            db, user_id, timestamp
        )
        recent_activity_block = build_recent_activity_block(
            note_items,
            website_items,
            conversation_items,
        )

        system_prompt = "\n\n".join(
            [
                system_prompt,
                context_guidance,
                open_block,
                recent_activity_block,
            ]
        )
        system_prompt = PromptContextService._truncate_text(
            system_prompt,
            PromptContextService.MAX_SYSTEM_PROMPT_CHARS,
        )

        first_message_prompt = build_first_message_prompt(
            settings_record,
            operating_system,
            timestamp,
        )
        first_message_prompt = PromptContextService._truncate_text(
            first_message_prompt,
            PromptContextService.MAX_FIRST_MESSAGE_CHARS,
        )

        return system_prompt, first_message_prompt

    @staticmethod
    def _start_of_today(now: datetime) -> datetime:
        """Return a timezone-aware start-of-day timestamp."""
        return datetime(now.year, now.month, now.day, tzinfo=now.tzinfo)

    @staticmethod
    def _truncate_text(value: str, max_chars: int) -> str:
        """Truncate a string to a maximum length."""
        if len(value) <= max_chars:
            return value
        return value[:max_chars]

    @staticmethod
    def _get_recent_activity(
        db: Session,
        user_id: str,
        now: datetime,
    ) -> tuple[list[dict], list[dict], list[dict]]:
        """Fetch recent activity items for prompt context.

        Args:
            db: Database session.
            user_id: Current user ID.
            now: Current timestamp.

        Returns:
            Tuple of (note_items, website_items, conversation_items).
        """
        start_of_day = PromptContextService._start_of_today(now)

        notes = (
            db.query(Note)
            .filter(Note.last_opened_at >= start_of_day)
            .filter(Note.user_id == user_id)
            .order_by(Note.last_opened_at.desc())
            .all()
        )
        websites = (
            db.query(Website)
            .filter(Website.last_opened_at >= start_of_day)
            .filter(Website.user_id == user_id)
            .order_by(Website.last_opened_at.desc())
            .all()
        )
        conversations = (
            db.query(Conversation)
            .filter(
                Conversation.user_id == user_id,
                Conversation.is_archived == False,
                Conversation.updated_at >= start_of_day,
            )
            .order_by(Conversation.updated_at.desc())
            .all()
        )

        note_items = [
            {
                "id": str(note.id),
                "title": note.title,
                "last_opened_at": note.last_opened_at.isoformat() if note.last_opened_at else None,
                "folder": note.metadata_.get("folder") if note.metadata_ else None,
            }
            for note in notes
        ]
        website_items = [
            {
                "id": str(website.id),
                "title": website.title,
                "last_opened_at": website.last_opened_at.isoformat() if website.last_opened_at else None,
                "domain": website.domain,
                "url": website.url_full or website.url,
            }
            for website in websites
        ]
        conversation_items = [
            {
                "id": str(conversation.id),
                "title": conversation.title,
                "last_opened_at": conversation.updated_at.isoformat() if conversation.updated_at else None,
                "message_count": conversation.message_count,
            }
            for conversation in conversations
        ]

        return note_items, website_items, conversation_items
