"""Conversation service for shared conversation business logic."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy.orm import Session, load_only
from sqlalchemy.orm.attributes import flag_modified

from api.exceptions import ConversationNotFoundError
from api.models.conversation import Conversation
from api.utils.search import build_text_search_filter


class ConversationService:
    """Service layer for conversation operations."""

    @staticmethod
    def is_hidden_message(message: dict) -> bool:
        """Return whether a stored transcript message is hidden from the UI."""
        return message.get("visibility") == "hidden"

    @classmethod
    def visible_messages(cls, messages: list[dict] | None) -> list[dict]:
        """Return transcript messages that should be visible in the UI."""
        return [
            message
            for message in (messages or [])
            if not cls.is_hidden_message(message)
        ]

    @classmethod
    def _apply_visible_message_metadata(cls, conversation: Conversation) -> None:
        """Keep derived conversation metadata aligned with visible transcript state."""
        visible_messages = cls.visible_messages(conversation.messages)
        conversation.message_count = len(visible_messages)

        first_message = None
        for message in visible_messages:
            first_content = message.get("content")
            if first_content:
                first_message = str(first_content)[:100]
                break
        conversation.first_message = first_message

    @staticmethod
    def create_conversation(db: Session, user_id: str, title: str) -> Conversation:
        """Create a new conversation.

        Args:
            db: Database session.
            user_id: Current user ID.
            title: Conversation title.

        Returns:
            Created conversation record.
        """
        conversation = Conversation(
            user_id=user_id,
            title=title,
            messages=[],
        )
        db.add(conversation)
        db.commit()
        db.refresh(conversation)
        return conversation

    @staticmethod
    def list_conversations(db: Session, user_id: str) -> list[Conversation]:
        """List all active conversations for a user.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            List of conversation records.
        """
        return (
            db.query(Conversation)
            .options(
                load_only(
                    Conversation.id,
                    Conversation.title,
                    Conversation.title_generated,
                    Conversation.created_at,
                    Conversation.updated_at,
                    Conversation.message_count,
                    Conversation.first_message,
                )
            )
            .filter(
                Conversation.user_id == user_id, Conversation.is_archived.is_(False)
            )
            .order_by(Conversation.updated_at.desc())
            .all()
        )

    @staticmethod
    def get_conversation(
        db: Session,
        user_id: str,
        conversation_id: UUID,
    ) -> Conversation:
        """Fetch a conversation for a user.

        Args:
            db: Database session.
            user_id: Current user ID.
            conversation_id: Conversation UUID.

        Returns:
            Conversation record.

        Raises:
            ConversationNotFoundError: If no conversation matches.
        """
        conversation = (
            db.query(Conversation)
            .filter(Conversation.id == conversation_id, Conversation.user_id == user_id)
            .first()
        )
        if not conversation:
            raise ConversationNotFoundError(str(conversation_id))
        return conversation

    @staticmethod
    def add_message(
        db: Session,
        user_id: str,
        conversation_id: UUID,
        message: dict,
    ) -> Conversation:
        """Append a message to a conversation.

        Args:
            db: Database session.
            user_id: Current user ID.
            conversation_id: Conversation UUID.
            message: Message payload dict.

        Returns:
            Updated conversation record.
        """
        conversation = ConversationService.get_conversation(
            db, user_id, conversation_id
        )
        messages = conversation.messages or []
        messages.append(message)
        conversation.messages = messages
        flag_modified(conversation, "messages")

        ConversationService._apply_visible_message_metadata(conversation)
        conversation.updated_at = datetime.now(UTC)

        db.commit()
        db.refresh(conversation)
        return conversation

    @staticmethod
    def add_messages(
        db: Session,
        user_id: str,
        conversation_id: UUID,
        messages_to_add: list[dict],
    ) -> Conversation:
        """Append multiple messages to a conversation in one commit.

        Args:
            db: Database session.
            user_id: Current user ID.
            conversation_id: Conversation UUID.
            messages_to_add: Message payload list to append in order.

        Returns:
            Updated conversation record.
        """
        conversation = ConversationService.get_conversation(
            db, user_id, conversation_id
        )
        existing_messages = conversation.messages or []
        existing_messages.extend(messages_to_add)
        conversation.messages = existing_messages
        flag_modified(conversation, "messages")

        ConversationService._apply_visible_message_metadata(conversation)
        conversation.updated_at = datetime.now(UTC)

        db.commit()
        db.refresh(conversation)
        return conversation

    @staticmethod
    def update_conversation(
        db: Session,
        user_id: str,
        conversation_id: UUID,
        *,
        title: str | None = None,
        title_generated: bool | None = None,
        is_archived: bool | None = None,
    ) -> Conversation:
        """Update conversation metadata.

        Args:
            db: Database session.
            user_id: Current user ID.
            conversation_id: Conversation UUID.
            title: Optional new title.
            title_generated: Optional title_generated flag.
            is_archived: Optional archive flag.

        Returns:
            Updated conversation record.
        """
        conversation = ConversationService.get_conversation(
            db, user_id, conversation_id
        )

        if title is not None:
            conversation.title = title
        if title_generated is not None:
            conversation.title_generated = title_generated
        if is_archived is not None:
            conversation.is_archived = is_archived
            conversation.updated_at = datetime.now(UTC)

        db.commit()
        db.refresh(conversation)
        return conversation

    @staticmethod
    def set_title(
        db: Session,
        user_id: str,
        conversation_id: UUID,
        title: str,
        *,
        generated: bool,
    ) -> Conversation:
        """Update conversation title and generated flag.

        Args:
            db: Database session.
            user_id: Current user ID.
            conversation_id: Conversation UUID.
            title: New title.
            generated: Whether the title was generated.

        Returns:
            Updated conversation record.
        """
        conversation = ConversationService.get_conversation(
            db, user_id, conversation_id
        )
        conversation.title = title
        conversation.title_generated = generated
        db.commit()
        db.refresh(conversation)
        return conversation

    @staticmethod
    def set_ai_provider_model(
        db: Session,
        user_id: str,
        conversation_id: UUID,
        *,
        provider: str,
        model: str,
    ) -> Conversation:
        """Persist effective assistant provider/model for a conversation."""
        conversation = ConversationService.get_conversation(
            db, user_id, conversation_id
        )
        conversation.ai_provider = provider
        conversation.ai_model = model
        conversation.updated_at = datetime.now(UTC)
        db.commit()
        db.refresh(conversation)
        return conversation

    @classmethod
    def search_conversations(
        cls,
        db: Session,
        user_id: str,
        query: str,
        limit: int = 10,
    ) -> list[Conversation]:
        """Search conversations by title, first message, or message content.

        Args:
            db: Database session.
            user_id: Current user ID.
            query: Search query string.
            limit: Max number of results.

        Returns:
            List of matching conversations.
        """
        conversations = (
            db.query(Conversation)
            .filter(
                Conversation.user_id == user_id,
                Conversation.is_archived.is_(False),
                build_text_search_filter(
                    [Conversation.title, Conversation.first_message],
                    query,
                ),
            )
            .order_by(Conversation.updated_at.desc())
            .limit(limit)
            .all()
        )

        message_candidates = (
            db.query(Conversation)
            .options(
                load_only(
                    Conversation.id,
                    Conversation.title,
                    Conversation.title_generated,
                    Conversation.created_at,
                    Conversation.updated_at,
                    Conversation.message_count,
                    Conversation.first_message,
                    Conversation.messages,
                )
            )
            .filter(
                Conversation.user_id == user_id,
                Conversation.is_archived.is_(False),
            )
            .order_by(Conversation.updated_at.desc())
            .all()
        )

        normalized_query = query.casefold()
        message_matches: list[Conversation] = []
        seen_ids = {str(item.id) for item in conversations}
        for conversation in message_candidates:
            if str(conversation.id) in seen_ids:
                continue

            if any(
                normalized_query in str(message.get("content", "")).casefold()
                for message in cls.visible_messages(conversation.messages)
            ):
                message_matches.append(conversation)

        all_matches = {str(item.id): item for item in conversations + message_matches}
        return sorted(
            all_matches.values(),
            key=lambda item: item.updated_at,
            reverse=True,
        )[:limit]
