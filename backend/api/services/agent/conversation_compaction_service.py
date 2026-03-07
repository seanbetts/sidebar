"""Persist deterministic hidden summary entries for compacted chat history."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.models.conversation import Conversation
from api.services.agent.request_assembly_service import RequestAssemblyService
from api.services.conversation_service import ConversationService


class ConversationCompactionService:
    """Compact older replay history into a hidden synthetic summary entry."""

    _MAX_SUMMARY_CHARS = 4_000
    _MAX_LINE_CHARS = 280

    @classmethod
    def count_replayable_messages(cls, messages: list[dict] | None) -> int:
        """Return how many stored messages still participate in replay."""
        return len(cls._replayable_message_indices(list(messages or [])))

    @classmethod
    def compact_conversation_history(
        cls,
        *,
        db: Session,
        user_id: str,
        conversation_id: UUID,
        replay_messages_to_compact: int,
        timestamp: str | None = None,
        summary_message_id: str | None = None,
    ) -> Conversation:
        """Hide compacted replay messages and insert a hidden summary entry."""
        conversation = ConversationService.get_conversation(
            db,
            user_id,
            conversation_id,
        )
        if replay_messages_to_compact <= 0:
            return conversation

        messages = list(conversation.messages or [])
        replayable_indices = cls._replayable_message_indices(messages)
        source_indices = replayable_indices[:replay_messages_to_compact]
        if not source_indices:
            return conversation

        source_messages = [messages[index] for index in source_indices]
        compacted_at = timestamp or datetime.now(UTC).isoformat()
        summary_id = summary_message_id or str(uuid4())

        for source_message in source_messages:
            compaction = dict(source_message.get("compaction") or {})
            compaction.update(
                {
                    "status": "compacted",
                    "summary_message_id": summary_id,
                    "compacted_at": compacted_at,
                }
            )
            source_message["compaction"] = compaction
            source_message["visibility"] = "hidden"

        summary_message = cls._build_summary_message(
            source_messages=source_messages,
            timestamp=compacted_at,
            summary_message_id=summary_id,
        )
        messages.insert(source_indices[-1] + 1, summary_message)

        conversation.messages = messages
        flag_modified(conversation, "messages")
        ConversationService._apply_visible_message_metadata(conversation)
        conversation.updated_at = datetime.now(UTC)

        db.commit()
        db.refresh(conversation)
        return conversation

    @classmethod
    def _replayable_message_indices(cls, messages: list[dict]) -> list[int]:
        """Return stored message indices that still participate in replay."""
        replayable_indices: list[int] = []
        for index, message in enumerate(messages):
            if RequestAssemblyService.is_bootstrap_message(message):
                continue
            if RequestAssemblyService.is_compacted_source_message(message):
                continue
            role = message.get("role")
            content = message.get("content")
            if role not in {"user", "assistant"} or content is None:
                continue
            replayable_indices.append(index)
        return replayable_indices

    @classmethod
    def _build_summary_message(
        cls,
        *,
        source_messages: list[dict],
        timestamp: str,
        summary_message_id: str,
    ) -> dict:
        """Build a hidden summary message for a compacted replay span."""
        source_message_ids = [
            str(message_id)
            for message in source_messages
            if (message_id := message.get("id")) is not None
        ]
        lines = ["Summary of earlier conversation:"]
        current_length = len(lines[0])

        for message in source_messages:
            role = "User" if message.get("role") == "user" else "Assistant"
            snippet = " ".join(str(message.get("content", "")).split())
            if len(snippet) > cls._MAX_LINE_CHARS:
                snippet = f"{snippet[: cls._MAX_LINE_CHARS - 3].rstrip()}..."
            line = f"- {role}: {snippet}"
            projected_length = current_length + 1 + len(line)
            if projected_length > cls._MAX_SUMMARY_CHARS:
                lines.append("- Additional compacted context omitted.")
                break
            lines.append(line)
            current_length = projected_length

        return {
            "id": summary_message_id,
            "role": "assistant",
            "content": "\n".join(lines),
            "status": "complete",
            "timestamp": timestamp,
            "visibility": "hidden",
            "kind": "conversation_compaction_summary",
            "compaction": {
                "status": "summary",
                "source_message_ids": source_message_ids,
                "message_count": len(source_messages),
                "generated_by": "deterministic_compaction_v1",
            },
        }
