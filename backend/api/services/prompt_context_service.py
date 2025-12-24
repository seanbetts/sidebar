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

    @staticmethod
    def build_prompts(
        db: Session,
        user_id: str,
        open_context: dict[str, Any] | None,
        user_agent: str | None,
        now: datetime | None = None,
    ) -> tuple[str, str]:
        timestamp = now or datetime.now(timezone.utc)
        settings_record = UserSettingsService.get_settings(db, user_id)
        location_fallback = (
            settings_record.location if settings_record and settings_record.location else "Unknown"
        )
        operating_system = detect_operating_system(user_agent)

        system_prompt = build_system_prompt(settings_record, location_fallback, timestamp)

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

        first_message_prompt = build_first_message_prompt(
            settings_record,
            operating_system,
            timestamp,
        )

        return system_prompt, first_message_prompt

    @staticmethod
    def _start_of_today(now: datetime) -> datetime:
        return datetime(now.year, now.month, now.day, tzinfo=now.tzinfo)

    @staticmethod
    def _get_recent_activity(
        db: Session,
        user_id: str,
        now: datetime,
    ) -> tuple[list[dict], list[dict], list[dict]]:
        start_of_day = PromptContextService._start_of_today(now)

        notes = (
            db.query(Note)
            .filter(Note.last_opened_at >= start_of_day)
            .order_by(Note.last_opened_at.desc())
            .all()
        )
        websites = (
            db.query(Website)
            .filter(Website.last_opened_at >= start_of_day)
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
