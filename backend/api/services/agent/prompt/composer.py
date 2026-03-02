"""Prompt context assembly for chat and tools."""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, TypedDict
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.orm import Session, load_only

from api.constants import PromptContextLimits
from api.models.conversation import Conversation
from api.models.file_ingestion import IngestedFile
from api.models.note import Note
from api.models.website import Website
from api.services.agent.prompt.sections import (
    CONTEXT_GUIDANCE_TEMPLATE,
    build_assistant_identity_block,
    build_assistant_soul_block,
    build_first_message_prompt,
    build_open_context_block,
    build_recent_activity_block,
    build_response_style_block,
    build_system_prompt,
    detect_operating_system,
    resolve_template,
)
from api.services.file_ingestion_service import FileIngestionService
from api.services.storage.service import get_storage_backend
from api.services.user_settings_service import UserSettingsService

logger = logging.getLogger(__name__)


class PromptSection(TypedDict):
    """Structured prompt section with source metadata."""

    id: str
    title: str
    source: str
    content: str
    chars: int


class PromptSectionReport(TypedDict):
    """Prompt section diagnostics without content payload."""

    id: str
    title: str
    source: str
    chars: int


class PromptDocument(TypedDict):
    """Prompt document payload with flattened text and section list."""

    text: str
    max_chars: int
    total_chars: int
    truncated: bool
    sections: list[PromptSection]


class PromptDocumentReport(TypedDict):
    """Prompt diagnostics payload for one prompt document."""

    total_chars: int
    max_chars: int
    truncated: bool
    sections: list[PromptSectionReport]


class PromptBuildResult(TypedDict):
    """Structured prompt payload used by chat runtime and tooling."""

    system_prompt: PromptDocument
    first_message_prompt: PromptDocument
    report: dict[str, PromptDocumentReport]


class PromptContextService:
    """Build prompt context blocks from DB and open UI state."""

    MAX_SYSTEM_PROMPT_CHARS = PromptContextLimits.MAX_SYSTEM_PROMPT_CHARS
    MAX_SYSTEM_CURRENT_OPEN_SECTION_CHARS = (
        PromptContextLimits.MAX_SYSTEM_CURRENT_OPEN_SECTION_CHARS
    )
    MAX_SYSTEM_RECENT_ACTIVITY_SECTION_CHARS = (
        PromptContextLimits.MAX_SYSTEM_RECENT_ACTIVITY_SECTION_CHARS
    )
    MAX_FIRST_MESSAGE_CHARS = PromptContextLimits.MAX_FIRST_MESSAGE_CHARS
    MAX_OPEN_FILE_CHARS = PromptContextLimits.MAX_OPEN_FILE_CHARS
    MAX_ATTACHMENT_CHARS = PromptContextLimits.MAX_ATTACHMENT_CHARS
    RECENT_ACTIVITY_CACHE_TTL = timedelta(minutes=5)
    _recent_activity_cache: dict[
        str, tuple[datetime, tuple[list[dict], list[dict], list[dict], list[dict]]]
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
        current_timezone: str | None = None,
        now: datetime | None = None,
        strict_system_prompt: bool = False,
        include_attachment_content: bool = True,
    ) -> PromptBuildResult:
        """Build structured system and first-message prompts.

        Args:
            db: Database session.
            user_id: Current user ID.
            open_context: Open note/website/file context payload.
            attachments: Optional file attachments metadata list.
            user_agent: User agent string.
            current_location: Current location label.
            current_location_levels: Structured location levels.
            current_weather: Weather payload.
            current_timezone: User timezone identifier.
            now: Optional timestamp override.
            strict_system_prompt: When True, reject requests that would require
                truncating the system prompt.
            include_attachment_content: When False, include attachment metadata
                but skip loading derivative content in the prompt context.

        Returns:
            Structured prompt bundle with flattened text and diagnostics.
        """
        timestamp = PromptContextService._resolve_timestamp(
            now=now,
            current_timezone=current_timezone,
        )
        settings_record = UserSettingsService.get_settings(db, user_id)
        resolved_location = current_location or "Current location not available"
        operating_system = detect_operating_system(user_agent)

        system_template = build_system_prompt(
            settings_record,
            resolved_location,
            current_location_levels,
            current_weather,
            timestamp,
        )
        context_guidance = resolve_template(
            CONTEXT_GUIDANCE_TEMPLATE,
            {
                "name": settings_record.name.strip()
                if settings_record and settings_record.name
                else "the user"
            },
        )
        assistant_identity = build_assistant_identity_block(settings_record)
        assistant_soul = build_assistant_soul_block(settings_record)
        response_style = build_response_style_block(settings_record)
        open_note = open_context.get("note") if isinstance(open_context, dict) else None
        open_website = (
            open_context.get("website") if isinstance(open_context, dict) else None
        )
        open_file = open_context.get("file") if isinstance(open_context, dict) else None
        resolved_file = PromptContextService._resolve_file_context(
            db, user_id, open_file, PromptContextService.MAX_OPEN_FILE_CHARS
        )
        resolved_attachments = PromptContextService._resolve_attachment_contexts(
            db,
            user_id,
            attachments or [],
            PromptContextService.MAX_ATTACHMENT_CHARS,
            include_content=include_attachment_content,
        )
        open_block = build_open_context_block(
            open_note,
            open_website,
            resolved_file,
            resolved_attachments,
        )

        note_items, website_items, conversation_items, file_items = (
            PromptContextService._get_recent_activity(db, user_id, timestamp)
        )
        recent_activity_block = build_recent_activity_block(
            note_items,
            website_items,
            conversation_items,
            file_items,
        )

        system_sections = [
            PromptContextService._build_section(
                section_id="message_context",
                title="Message Context",
                source="system_template",
                content=system_template,
            ),
            PromptContextService._build_section(
                section_id="assistant_identity",
                title="Assistant Identity",
                source="assistant_identity",
                content=assistant_identity,
            ),
            PromptContextService._build_section(
                section_id="assistant_soul",
                title="Assistant Soul",
                source="assistant_soul",
                content=assistant_soul,
            ),
            PromptContextService._build_section(
                section_id="response_style",
                title="Response Style",
                source="response_style",
                content=response_style,
            ),
            PromptContextService._build_section(
                section_id="context_guidance",
                title="Context Guidance",
                source="context_guidance_template",
                content=context_guidance,
            ),
            PromptContextService._build_section(
                section_id="current_open",
                title="Current Open Context",
                source="open_context",
                content=open_block,
            ),
            PromptContextService._build_section(
                section_id="recent_activity",
                title="Recent Activity",
                source="recent_activity",
                content=recent_activity_block,
            ),
        ]
        system_prompt_document = PromptContextService._build_prompt_document(
            system_sections,
            PromptContextService.MAX_SYSTEM_PROMPT_CHARS,
            section_char_limits={
                "current_open": (
                    PromptContextService.MAX_SYSTEM_CURRENT_OPEN_SECTION_CHARS
                ),
                "recent_activity": (
                    PromptContextService.MAX_SYSTEM_RECENT_ACTIVITY_SECTION_CHARS
                ),
            },
        )

        first_message_text = build_first_message_prompt(
            settings_record,
            operating_system,
            timestamp,
        )
        first_message_sections = [
            PromptContextService._build_section(
                section_id="first_message",
                title="First Message Context",
                source="first_message_template",
                content=first_message_text,
            )
        ]
        first_message_document = PromptContextService._build_prompt_document(
            first_message_sections,
            PromptContextService.MAX_FIRST_MESSAGE_CHARS,
        )

        report = {
            "system_prompt": PromptContextService._build_prompt_report(
                system_prompt_document
            ),
            "first_message_prompt": PromptContextService._build_prompt_report(
                first_message_document
            ),
        }
        if strict_system_prompt and report["system_prompt"]["truncated"]:
            raise ValueError(
                "System prompt exceeds maximum size "
                f"({report['system_prompt']['total_chars']} > "
                f"{report['system_prompt']['max_chars']})"
            )

        return {
            "system_prompt": system_prompt_document,
            "first_message_prompt": first_message_document,
            "report": report,
        }

    @staticmethod
    def _build_section(
        *,
        section_id: str,
        title: str,
        source: str,
        content: str,
    ) -> PromptSection:
        """Create a prompt section structure."""
        section_text = content or ""
        return {
            "id": section_id,
            "title": title,
            "source": source,
            "content": section_text,
            "chars": len(section_text),
        }

    @staticmethod
    def _build_prompt_document(
        sections: list[PromptSection],
        max_chars: int,
        section_char_limits: dict[str, int] | None = None,
    ) -> PromptDocument:
        """Build a flattened prompt document from ordered sections."""
        original_sections = PromptContextService._normalize_sections(sections)
        normalized_sections = PromptContextService._normalize_sections(sections)
        if section_char_limits:
            normalized_sections = PromptContextService._apply_section_char_limits(
                normalized_sections,
                section_char_limits,
            )
        joined = PromptContextService._join_sections(normalized_sections)
        original_joined = PromptContextService._join_sections(original_sections)

        if len(joined) > max_chars:
            normalized_sections = PromptContextService._fit_sections_to_budget(
                normalized_sections,
                max_chars=max_chars,
            )
            joined = PromptContextService._join_sections(normalized_sections)

        truncated = joined != original_joined or len(joined) > max_chars
        text = PromptContextService._truncate_text(joined, max_chars)
        return {
            "text": text,
            "max_chars": max_chars,
            "total_chars": len(text),
            "truncated": truncated,
            "sections": normalized_sections,
        }

    @staticmethod
    def _build_prompt_report(document: PromptDocument) -> PromptDocumentReport:
        """Build prompt diagnostics without section content."""
        section_reports: list[PromptSectionReport] = [
            {
                "id": section["id"],
                "title": section["title"],
                "source": section["source"],
                "chars": section["chars"],
            }
            for section in document["sections"]
        ]
        return {
            "total_chars": document["total_chars"],
            "max_chars": document["max_chars"],
            "truncated": document["truncated"],
            "sections": section_reports,
        }

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
        include_content: bool = True,
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
            content = None
            if include_content:
                derivative = FileIngestionService.get_derivative(db, file_uuid, "ai_md")
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

    @staticmethod
    def _resolve_timestamp(
        *,
        now: datetime | None,
        current_timezone: str | None,
    ) -> datetime:
        """Resolve current timestamp in the user's timezone when available."""
        timestamp = now or datetime.now(UTC)
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=UTC)

        timezone_name = (current_timezone or "").strip()
        if not timezone_name:
            return timestamp
        try:
            user_timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError:
            logger.warning(
                "Invalid current_timezone received",
                extra={"timezone": timezone_name},
            )
            return timestamp
        return timestamp.astimezone(user_timezone)

    @staticmethod
    def _normalize_sections(sections: list[PromptSection]) -> list[PromptSection]:
        """Copy sections and recalculate char counts from current content."""
        normalized: list[PromptSection] = []
        for section in sections:
            content = section["content"] or ""
            normalized.append(
                {
                    "id": section["id"],
                    "title": section["title"],
                    "source": section["source"],
                    "content": content,
                    "chars": len(content),
                }
            )
        return normalized

    @staticmethod
    def _join_sections(sections: list[PromptSection]) -> str:
        """Join non-empty section content into the flattened document."""
        return "\n\n".join(
            section["content"] for section in sections if section["content"]
        )

    @classmethod
    def _apply_section_char_limits(
        cls,
        sections: list[PromptSection],
        section_char_limits: dict[str, int],
    ) -> list[PromptSection]:
        """Apply per-section caps before fitting the full prompt budget."""
        updated = cls._normalize_sections(sections)
        for index, section in enumerate(updated):
            max_chars = section_char_limits.get(section["id"])
            if max_chars is None or max_chars <= 0:
                continue
            content = cls._truncate_section_content(section["content"], max_chars)
            updated[index]["content"] = content
            updated[index]["chars"] = len(content)
        return updated

    @classmethod
    def _fit_sections_to_budget(
        cls,
        sections: list[PromptSection],
        *,
        max_chars: int,
    ) -> list[PromptSection]:
        """Reduce large sections while preserving section wrappers where possible."""
        updated = cls._normalize_sections(sections)
        shrink_order = [
            "current_open",
            "recent_activity",
            "message_context",
            "assistant_soul",
            "assistant_identity",
            "response_style",
            "context_guidance",
        ]

        while len(cls._join_sections(updated)) > max_chars:
            overflow = len(cls._join_sections(updated)) - max_chars
            reduced = False

            for section_id in shrink_order:
                index = next(
                    (
                        i
                        for i, section in enumerate(updated)
                        if section["id"] == section_id
                    ),
                    None,
                )
                if index is None:
                    continue
                current_content = updated[index]["content"]
                minimum_chars = cls._minimum_section_chars(current_content)
                if len(current_content) <= minimum_chars:
                    continue

                reduce_by = max(overflow, 256)
                target_chars = max(minimum_chars, len(current_content) - reduce_by)
                next_content = cls._truncate_section_content(
                    current_content,
                    target_chars,
                )
                if len(next_content) >= len(current_content):
                    continue
                updated[index]["content"] = next_content
                updated[index]["chars"] = len(next_content)
                reduced = True
                if len(cls._join_sections(updated)) <= max_chars:
                    break

            if not reduced:
                break
        return updated

    @staticmethod
    def _minimum_section_chars(content: str) -> int:
        """Return minimum chars to keep wrapper tags intact when possible."""
        wrapped = PromptContextService._extract_wrapped_section(content)
        if wrapped is None:
            return min(len(content), 64)
        opening_tag, _inner, closing_tag = wrapped
        return len(opening_tag) + len(closing_tag) + 2

    @staticmethod
    def _truncate_section_content(content: str, max_chars: int) -> str:
        """Truncate content while preserving wrapper tags for XML-like blocks."""
        if len(content) <= max_chars:
            return content
        wrapped = PromptContextService._extract_wrapped_section(content)
        if wrapped is None:
            return PromptContextService._truncate_text(content, max_chars)

        opening_tag, inner, closing_tag = wrapped
        overhead = len(opening_tag) + len(closing_tag) + 2
        available = max_chars - overhead
        if available <= 0:
            return PromptContextService._truncate_text(content, max_chars)
        return f"{opening_tag}\n{inner[:available]}\n{closing_tag}"

    @staticmethod
    def _extract_wrapped_section(content: str) -> tuple[str, str, str] | None:
        """Extract opening tag, inner content, and closing tag for wrapped sections."""
        stripped = content.strip()
        if not stripped.startswith("<"):
            return None
        opening_end = stripped.find(">")
        if opening_end <= 0:
            return None
        opening_tag = stripped[: opening_end + 1]
        if opening_tag.startswith("</"):
            return None
        tag_name = opening_tag[1:-1].strip()
        if not tag_name:
            return None
        closing_tag = f"</{tag_name}>"
        if not stripped.endswith(closing_tag):
            return None
        inner = stripped[opening_end + 1 : -len(closing_tag)]
        return opening_tag, inner, closing_tag

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
            .options(
                load_only(
                    Note.id,
                    Note.title,
                    Note.last_opened_at,
                    Note.folder_path,
                )
            )
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
            .options(
                load_only(
                    Conversation.id,
                    Conversation.title,
                    Conversation.updated_at,
                    Conversation.message_count,
                )
            )
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
                "last_opened_at": note.last_opened_at.isoformat()
                if note.last_opened_at
                else None,
                "folder": note.folder_path or None,
            }
            for note in notes
        ]
        website_items = [
            {
                "id": str(website.id),
                "title": website.title,
                "last_opened_at": website.last_opened_at.isoformat()
                if website.last_opened_at
                else None,
                "domain": website.domain,
                "url": website.url_full or website.url,
            }
            for website in websites
        ]
        conversation_items = [
            {
                "id": str(conversation.id),
                "title": conversation.title,
                "last_opened_at": conversation.updated_at.isoformat()
                if conversation.updated_at
                else None,
                "message_count": conversation.message_count,
            }
            for conversation in conversations
        ]
        file_items = [
            {
                "id": str(file.id),
                "filename": file.filename_original,
                "last_opened_at": file.last_opened_at.isoformat()
                if file.last_opened_at
                else None,
                "mime": file.mime_original,
            }
            for file in files
        ]

        items = (note_items, website_items, conversation_items, file_items)
        cls._recent_activity_cache[user_id] = (now, items)
        return items
