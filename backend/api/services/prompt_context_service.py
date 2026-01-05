"""Prompt context assembly for chat and tools."""
from __future__ import annotations

from datetime import datetime, timezone, timedelta
import logging
from typing import Any

from sqlalchemy.orm import Session, load_only

from api.models.conversation import Conversation
from api.models.note import Note
from api.models.website import Website
from api.models.file_ingestion import IngestedFile
from api.prompts import (
    build_first_message_prompt,
    build_system_prompt,
    build_recent_activity_block,
    build_open_context_block,
    detect_operating_system,
    resolve_template,
    CONTEXT_GUIDANCE_TEMPLATE,
)
from api.services.file_ingestion_service import FileIngestionService
from api.constants import PromptContextLimits
from api.services.storage.service import get_storage_backend
import uuid
from api.services.user_settings_service import UserSettingsService

logger = logging.getLogger(__name__)


class PromptContextService:
    """Build prompt context blocks from DB and open UI state."""

    MAX_SYSTEM_PROMPT_CHARS = PromptContextLimits.MAX_SYSTEM_PROMPT_CHARS
    MAX_FIRST_MESSAGE_CHARS = PromptContextLimits.MAX_FIRST_MESSAGE_CHARS
    MAX_OPEN_FILE_CHARS = PromptContextLimits.MAX_OPEN_FILE_CHARS
    MAX_ATTACHMENT_CHARS = PromptContextLimits.MAX_ATTACHMENT_CHARS
    RECENT_ACTIVITY_CACHE_TTL = timedelta(minutes=5)
    _recent_activity_cache: dict[
        str,
        tuple[datetime, tuple[list[dict], list[dict], list[dict], list[dict]]]
    ] = {}

    @staticmethod
    def build_prompts(
        db: Session,
        user_id: str,
        open_context: dict[str, Any] | None,
        attachments: list[dict[str, Any]] | None,
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
            open_context: Open note/website/file context payload.
            attachments: Optional file attachments metadata list.
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
        open_file = open_context.get("file") if isinstance(open_context, dict) else None
        resolved_file = PromptContextService._resolve_file_context(
            db, user_id, open_file, PromptContextService.MAX_OPEN_FILE_CHARS
        )
        resolved_attachments = PromptContextService._resolve_attachment_contexts(
            db, user_id, attachments or [], PromptContextService.MAX_ATTACHMENT_CHARS
        )
        open_block = build_open_context_block(
            open_note,
            open_website,
            resolved_file,
            resolved_attachments,
        )

        note_items, website_items, conversation_items, file_items = PromptContextService._get_recent_activity(
            db, user_id, timestamp
        )
        recent_activity_block = build_recent_activity_block(
            note_items,
            website_items,
            conversation_items,
            file_items,
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
    def _resolve_file_context(
        db: Session,
        user_id: str,
        file_ref: dict[str, Any] | None,
        max_chars: int,
    ) -> dict[str, Any] | None:
        if not file_ref:
            return None
        file_id = file_ref.get("id") or file_ref.get("file_id")
        if not file_id:
            return None
        try:
            file_uuid = uuid.UUID(str(file_id))
        except ValueError:
            return None
        record = FileIngestionService.get_file(db, user_id, file_uuid)
        if not record:
            return None
        derivative = FileIngestionService.get_derivative(db, file_uuid, "ai_md")
        content = None
        if derivative:
            storage = get_storage_backend()
            try:
                content_bytes = storage.get_object(derivative.storage_key)
                content = content_bytes.decode("utf-8", errors="ignore")
            except Exception as exc:
                logger.warning(
                    "Failed to load file context content",
                    exc_info=exc,
                    extra={
                        "user_id": user_id,
                        "file_id": str(file_uuid),
                        "storage_key": derivative.storage_key,
                    },
                )
                content = None
        if content:
            content = PromptContextService._truncate_text(content, max_chars)
        return {
            "id": str(record.id),
            "filename": record.filename_original,
            "mime": record.mime_original,
            "category": file_ref.get("category"),
            "content": content,
        }

    @staticmethod
    def _resolve_attachment_contexts(
        db: Session,
        user_id: str,
        attachments: list[dict[str, Any]],
        max_chars: int,
    ) -> list[dict[str, Any]]:
        resolved: list[dict[str, Any]] = []
        for attachment in attachments:
            file_id = attachment.get("file_id") or attachment.get("id")
            if not file_id:
                continue
            try:
                file_uuid = uuid.UUID(str(file_id))
            except ValueError:
                continue
            record = FileIngestionService.get_file(db, user_id, file_uuid)
            if not record:
                continue
            derivative = FileIngestionService.get_derivative(db, file_uuid, "ai_md")
            content = None
            if derivative:
                storage = get_storage_backend()
                try:
                    content_bytes = storage.get_object(derivative.storage_key)
                    content = content_bytes.decode("utf-8", errors="ignore")
                except Exception as exc:
                    logger.warning(
                        "Failed to load attachment context content",
                        exc_info=exc,
                        extra={
                            "user_id": user_id,
                            "file_id": str(file_uuid),
                            "storage_key": derivative.storage_key,
                        },
                    )
                    content = None
            if content:
                content = PromptContextService._truncate_text(content, max_chars)
            resolved.append(
                {
                    "id": str(record.id),
                    "filename": record.filename_original,
                    "mime": record.mime_original,
                    "category": attachment.get("category"),
                    "content": content,
                }
            )
        return resolved

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

    @classmethod
    def _get_recent_activity(
        cls,
        db: Session,
        user_id: str,
        now: datetime,
    ) -> tuple[list[dict], list[dict], list[dict], list[dict]]:
        """Fetch recent activity items for prompt context.

        Args:
            db: Database session.
            user_id: Current user ID.
            now: Current timestamp.

        Returns:
            Tuple of (note_items, website_items, conversation_items, file_items).
        """
        cached = cls._recent_activity_cache.get(user_id)
        if cached:
            cached_at, cached_items = cached
            if now - cached_at <= cls.RECENT_ACTIVITY_CACHE_TTL:
                return cached_items
            cls._recent_activity_cache.pop(user_id, None)

        start_of_day = PromptContextService._start_of_today(now)

        notes = (
            db.query(Note)
            .options(load_only(Note.id, Note.title, Note.last_opened_at, Note.metadata_))
            .filter(Note.last_opened_at >= start_of_day)
            .filter(Note.user_id == user_id)
            .order_by(Note.last_opened_at.desc())
            .all()
        )
        websites = (
            db.query(Website)
            .options(
                load_only(
                    Website.id,
                    Website.title,
                    Website.last_opened_at,
                    Website.domain,
                    Website.url_full,
                    Website.url,
                )
            )
            .filter(Website.last_opened_at >= start_of_day)
            .filter(Website.user_id == user_id)
            .order_by(Website.last_opened_at.desc())
            .all()
        )
        conversations = (
            db.query(Conversation)
            .options(load_only(Conversation.id, Conversation.title, Conversation.updated_at, Conversation.message_count))
            .filter(
                Conversation.user_id == user_id,
                Conversation.is_archived.is_(False),
                Conversation.updated_at >= start_of_day,
            )
            .order_by(Conversation.updated_at.desc())
            .all()
        )
        files = (
            db.query(IngestedFile)
            .options(
                load_only(
                    IngestedFile.id,
                    IngestedFile.filename_original,
                    IngestedFile.last_opened_at,
                    IngestedFile.mime_original,
                )
            )
            .filter(
                IngestedFile.last_opened_at >= start_of_day,
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
            )
            .order_by(IngestedFile.last_opened_at.desc())
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
        file_items = [
            {
                "id": str(file.id),
                "filename": file.filename_original,
                "last_opened_at": file.last_opened_at.isoformat() if file.last_opened_at else None,
                "mime": file.mime_original,
            }
            for file in files
        ]

        items = (note_items, website_items, conversation_items, file_items)
        cls._recent_activity_cache[user_id] = (now, items)
        return items
