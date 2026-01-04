"""Conversation service for shared conversation business logic."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import cast, or_, String
from sqlalchemy.orm import Session, load_only
from sqlalchemy.orm.attributes import flag_modified

from api.exceptions import ConversationNotFoundError
from api.models.conversation import Conversation


class ConversationService:
    """Service layer for conversation operations."""

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
            .options(load_only(
                Conversation.id,
                Conversation.title,
                Conversation.title_generated,
                Conversation.created_at,
                Conversation.updated_at,
                Conversation.message_count,
                Conversation.first_message,
            ))
            .filter(Conversation.user_id == user_id, Conversation.is_archived == False)
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
        conversation = ConversationService.get_conversation(db, user_id, conversation_id)
        messages = conversation.messages or []
        messages.append(message)
        conversation.messages = messages
        flag_modified(conversation, "messages")

        conversation.message_count = len(messages)
        conversation.updated_at = datetime.now(timezone.utc)

        if conversation.message_count == 1:
            first_content = message.get("content")
            if first_content:
                conversation.first_message = str(first_content)[:100]

        db.commit()
        db.refresh(conversation)
        return conversation

    @staticmethod
    def update_conversation(
        db: Session,
        user_id: str,
        conversation_id: UUID,
        *,
        title: Optional[str] = None,
        title_generated: Optional[bool] = None,
        is_archived: Optional[bool] = None,
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
        conversation = ConversationService.get_conversation(db, user_id, conversation_id)

        if title is not None:
            conversation.title = title
        if title_generated is not None:
            conversation.title_generated = title_generated
        if is_archived is not None:
            conversation.is_archived = is_archived
            conversation.updated_at = datetime.now(timezone.utc)

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
        conversation = ConversationService.get_conversation(db, user_id, conversation_id)
        conversation.title = title
        conversation.title_generated = generated
        db.commit()
        db.refresh(conversation)
        return conversation

    @staticmethod
    def search_conversations(
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
                Conversation.is_archived == False,
                or_(
                    Conversation.title.ilike(f"%{query}%"),
                    Conversation.first_message.ilike(f"%{query}%"),
                ),
            )
            .order_by(Conversation.updated_at.desc())
            .limit(limit)
            .all()
        )

        message_matches = (
            db.query(Conversation)
            .filter(
                Conversation.user_id == user_id,
                Conversation.is_archived == False,
                cast(Conversation.messages, String).ilike(f"%{query}%"),
            )
            .order_by(Conversation.updated_at.desc())
            .limit(limit)
            .all()
        )

        all_matches = {str(item.id): item for item in conversations + message_matches}
        return list(all_matches.values())[:limit]
