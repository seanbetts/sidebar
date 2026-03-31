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
from api.services.agent.prompt.document_builder import (
    PromptDocument,
    PromptDocumentReport,
    build_prompt_document,
    build_prompt_report,
    build_section,
    truncate_text,
)
from api.services.agent.prompt.sections import (
    CONTEXT_GUIDANCE_TEMPLATE,
    build_assistant_identity_block,
    build_assistant_soul_block,
    build_first_message_prompt,
    build_onboarding_block,
    build_open_context_block,
    build_recent_activity_block,
    build_response_style_block,
    build_system_prompt,
    detect_operating_system,
    resolve_template,
)
from api.services.file_ingestion_service import FileIngestionService
from api.services.knowledge.provider import get_docs_indexer
from api.services.storage.service import get_storage_backend
from api.services.user_settings_service import UserSettingsService

logger = logging.getLogger(__name__)


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
        blocked_skill_summaries: list[dict[str, Any]] | None = None,
        loaded_instructions: list[dict[str, Any]] | None = None,
        loaded_examples: list[dict[str, Any]] | None = None,
        onboarding_state: dict[str, Any] | None = None,
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
            onboarding_state: Derived onboarding contract for the current user.
            blocked_skill_summaries: Compact blocked capability metadata for
                reconnect or remediation guidance.
            loaded_instructions: Full selected-skill instruction documents.
            loaded_examples: Full selected-skill example documents.
            strict_system_prompt: When True, reject requests that still exceed
                the overall system prompt budget after per-section caps are
                applied.
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
        onboarding_block = build_onboarding_block(onboarding_state)
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
        selected_capabilities_block = (
            PromptContextService._build_selected_capabilities_block(
                loaded_instructions or [],
                loaded_examples or [],
            )
        )
        blocked_capabilities_block = (
            PromptContextService._build_blocked_capabilities_block(
                blocked_skill_summaries or []
            )
        )

        try:
            product_knowledge_brief = get_docs_indexer().product_knowledge_brief
        except RuntimeError:
            logger.warning(
                "DocsIndexer not initialised; product_knowledge section will be empty"
            )
            product_knowledge_brief = ""

        system_sections = [
            build_section(
                section_id="message_context",
                title="Message Context",
                source="system_template",
                content=system_template,
            ),
            build_section(
                section_id="assistant_identity",
                title="Assistant Identity",
                source="assistant_identity",
                content=assistant_identity,
            ),
            build_section(
                section_id="assistant_soul",
                title="Assistant Soul",
                source="assistant_soul",
                content=assistant_soul,
            ),
            build_section(
                section_id="response_style",
                title="Response Style",
                source="response_style",
                content=response_style,
            ),
            build_section(
                section_id="context_guidance",
                title="Context Guidance",
                source="context_guidance_template",
                content=context_guidance,
            ),
            build_section(
                section_id="product_knowledge",
                title="Product Knowledge",
                source="docs_indexer",
                content=product_knowledge_brief,
            ),
            build_section(
                section_id="selected_capabilities",
                title="Selected Capabilities",
                source="capability_loader",
                content=selected_capabilities_block,
            ),
            build_section(
                section_id="blocked_capabilities",
                title="Blocked Capabilities",
                source="capability_resolver",
                content=blocked_capabilities_block,
            ),
            build_section(
                section_id="current_open",
                title="Current Open Context",
                source="open_context",
                content=open_block,
            ),
            build_section(
                section_id="recent_activity",
                title="Recent Activity",
                source="recent_activity",
                content=recent_activity_block,
            ),
        ]
        if onboarding_block:
            system_sections.insert(
                4,
                build_section(
                    section_id="onboarding_state",
                    title="Onboarding State",
                    source="onboarding_state",
                    content=onboarding_block,
                ),
            )
        system_prompt_document = build_prompt_document(
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
            build_section(
                section_id="first_message",
                title="First Message Context",
                source="first_message_template",
                content=first_message_text,
            )
        ]
        first_message_document = build_prompt_document(
            first_message_sections,
            PromptContextService.MAX_FIRST_MESSAGE_CHARS,
        )

        report = {
            "system_prompt": build_prompt_report(system_prompt_document),
            "first_message_prompt": build_prompt_report(first_message_document),
        }
        if strict_system_prompt and report["system_prompt"]["truncated_by_budget"]:
            raise ValueError(
                "System prompt exceeds maximum size "
                f"({report['system_prompt']['constrained_total_chars']} > "
                f"{report['system_prompt']['max_chars']})"
            )

        return {
            "system_prompt": system_prompt_document,
            "first_message_prompt": first_message_document,
            "report": report,
        }

    @staticmethod
    def _build_selected_capabilities_block(
        loaded_instructions: list[dict[str, Any]],
        loaded_examples: list[dict[str, Any]],
    ) -> str:
        """Render selected capability instructions/examples into one block."""
        if not loaded_instructions and not loaded_examples:
            return ""

        lines = ["Selected skill instructions and examples for this turn:"]
        for document in loaded_instructions:
            skill_id = str(document.get("skill_id", "unknown-skill"))
            ref = str(document.get("ref", ""))
            content = str(document.get("content", "")).strip()
            lines.extend(
                [
                    "",
                    f"Skill: {skill_id}",
                    f"Instruction Ref: {ref}",
                    content,
                ]
            )
        for document in loaded_examples:
            skill_id = str(document.get("skill_id", "unknown-skill"))
            ref = str(document.get("ref", ""))
            content = str(document.get("content", "")).strip()
            lines.extend(
                [
                    "",
                    f"Example Skill: {skill_id}",
                    f"Example Ref: {ref}",
                    content,
                ]
            )
        body = "\n".join(lines).strip()
        return f"<selected_capabilities>\n\n{body}\n\n</selected_capabilities>"

    @staticmethod
    def _build_blocked_capabilities_block(
        blocked_skill_summaries: list[dict[str, Any]],
    ) -> str:
        """Render terse blocked-skill remediation guidance when relevant."""
        if not blocked_skill_summaries:
            return ""

        lines = ["Blocked skills that may need user remediation:"]
        for summary in blocked_skill_summaries:
            skill_id = str(summary.get("skill_id", "unknown-skill"))
            reason = str(
                summary.get("availability_reason")
                or summary.get("availability_status")
                or "unavailable"
            ).strip()
            remediation = summary.get("availability_remediation")
            remediation_text = ""
            if isinstance(remediation, dict):
                action = str(remediation.get("action", "")).strip()
                provider = str(remediation.get("provider", "")).strip()
                parts = [part for part in (action, provider) if part]
                if parts:
                    remediation_text = f"; remediation: {' '.join(parts)}"
            lines.append(f"- {skill_id}: {reason}{remediation_text}")
        body = "\n".join(lines)
        return f"<blocked_capabilities>\n\n{body}\n\n</blocked_capabilities>"

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
            content = truncate_text(content, max_chars)
        return {
            "id": str(record.id),
            "filename": record.filename_original,
            "path": record.path,
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
                content = truncate_text(content, max_chars)
            resolved.append(
                {
                    "id": str(record.id),
                    "filename": record.filename_original,
                    "path": record.path,
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
