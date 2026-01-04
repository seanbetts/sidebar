"""Conversations API router with JSONB message storage."""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session, load_only
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy import or_, func, cast, String
from typing import List
from uuid import UUID
from datetime import datetime, timezone

from api.db.session import get_db
from api.db.dependencies import get_current_user_id
from api.models.conversation import Conversation
from api.exceptions import ConversationNotFoundError
from pydantic import BaseModel


# Pydantic models for request/response
class MessageCreate(BaseModel):
    """Message to add to conversation."""
    id: str
    role: str
    content: str
    status: str | None = None
    timestamp: str
    toolCalls: list | None = None
    error: str | None = None


class ConversationCreate(BaseModel):
    """Create conversation request."""
    title: str = "New Chat"


class ConversationUpdate(BaseModel):
    """Update conversation request."""
    title: str | None = None
    titleGenerated: bool | None = None
    isArchived: bool | None = None


class ConversationResponse(BaseModel):
    """Conversation response without messages."""
    id: str
    title: str
    titleGenerated: bool
    createdAt: str
    updatedAt: str
    messageCount: int
    firstMessage: str | None


class ConversationWithMessages(ConversationResponse):
    """Conversation response with messages."""
    messages: list


router = APIRouter(prefix="/conversations", tags=["conversations"])


@router.post("", response_model=ConversationResponse)
@router.post("/", response_model=ConversationResponse)
async def create_conversation(
    data: ConversationCreate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Create a new conversation."""
    conversation = Conversation(
        user_id=user_id,
        title=data.title,
        messages=[]
    )
    db.add(conversation)
    db.commit()

    return ConversationResponse(
        id=str(conversation.id),
        title=conversation.title,
        titleGenerated=conversation.title_generated,
        createdAt=conversation.created_at.isoformat(),
        updatedAt=conversation.updated_at.isoformat(),
        messageCount=conversation.message_count,
        firstMessage=conversation.first_message
    )


@router.get("", response_model=List[ConversationResponse])
@router.get("/", response_model=List[ConversationResponse])
async def list_conversations(
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """List all conversations for the current user."""
    conversations = db.query(Conversation)\
        .options(load_only(
            Conversation.id,
            Conversation.title,
            Conversation.title_generated,
            Conversation.created_at,
            Conversation.updated_at,
            Conversation.message_count,
            Conversation.first_message,
        ))\
        .filter(Conversation.user_id == user_id, Conversation.is_archived == False)\
        .order_by(Conversation.updated_at.desc())\
        .all()

    return [
        ConversationResponse(
            id=str(c.id),
            title=c.title,
            titleGenerated=c.title_generated,
            createdAt=c.created_at.isoformat(),
            updatedAt=c.updated_at.isoformat(),
            messageCount=c.message_count,
            firstMessage=c.first_message
        )
        for c in conversations
    ]


@router.get("/{conversation_id}", response_model=ConversationWithMessages)
async def get_conversation(
    conversation_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Get a single conversation with all messages."""
    conversation = db.query(Conversation).filter(
        Conversation.id == conversation_id,
        Conversation.user_id == user_id
    ).first()

    if not conversation:
        raise ConversationNotFoundError(str(conversation_id))

    return ConversationWithMessages(
        id=str(conversation.id),
        title=conversation.title,
        titleGenerated=conversation.title_generated,
        createdAt=conversation.created_at.isoformat(),
        updatedAt=conversation.updated_at.isoformat(),
        messageCount=conversation.message_count,
        firstMessage=conversation.first_message,
        messages=conversation.messages or []
    )


@router.post("/{conversation_id}/messages")
async def add_message(
    conversation_id: UUID,
    message: MessageCreate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Add a message to a conversation."""
    conversation = db.query(Conversation).filter(
        Conversation.id == conversation_id,
        Conversation.user_id == user_id
    ).first()

    if not conversation:
        raise ConversationNotFoundError(str(conversation_id))

    # Convert message to dict
    message_dict = message.model_dump()

    # Append message to JSONB array
    messages = conversation.messages or []
    messages.append(message_dict)
    conversation.messages = messages
    flag_modified(conversation, 'messages')  # Mark JSONB field as modified

    # Update conversation metadata
    conversation.message_count = len(messages)
    conversation.updated_at = datetime.now(timezone.utc)

    # Update first_message if this is the first message
    if conversation.message_count == 1:
        conversation.first_message = message.content[:100]

    db.commit()

    return {"success": True, "messageCount": conversation.message_count}


@router.put("/{conversation_id}")
async def update_conversation(
    conversation_id: UUID,
    updates: ConversationUpdate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Update conversation metadata."""
    conversation = db.query(Conversation).filter(
        Conversation.id == conversation_id,
        Conversation.user_id == user_id
    ).first()

    if not conversation:
        raise ConversationNotFoundError(str(conversation_id))

    if updates.title is not None:
        conversation.title = updates.title
    if updates.titleGenerated is not None:
        conversation.title_generated = updates.titleGenerated
    if updates.isArchived is not None:
        conversation.is_archived = updates.isArchived
        # Only update timestamp when archiving (actual conversation state change)
        conversation.updated_at = datetime.now(timezone.utc)

    db.commit()

    return {"success": True}


@router.delete("/{conversation_id}")
async def delete_conversation(
    conversation_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Archive (soft delete) a conversation."""
    conversation = db.query(Conversation).filter(
        Conversation.id == conversation_id,
        Conversation.user_id == user_id
    ).first()

    if not conversation:
        raise ConversationNotFoundError(str(conversation_id))

    conversation.is_archived = True
    conversation.updated_at = datetime.now(timezone.utc)
    db.commit()

    return {"success": True}


@router.post("/search", response_model=List[ConversationResponse])
async def search_conversations(
    query: str,
    limit: int = 10,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Full-text search across conversations and messages."""
    # Search in conversation titles and first messages using ILIKE
    conversations = db.query(Conversation).filter(
        Conversation.user_id == user_id,
        Conversation.is_archived == False,
        or_(
            Conversation.title.ilike(f'%{query}%'),
            Conversation.first_message.ilike(f'%{query}%')
        )
    ).order_by(Conversation.updated_at.desc()).limit(limit).all()

    # Also search in message content within JSONB
    # Use PostgreSQL JSONB operators to search within messages array
    message_matches = db.query(Conversation).filter(
        Conversation.user_id == user_id,
        Conversation.is_archived == False,
        cast(Conversation.messages, String).ilike(f'%{query}%')
    ).order_by(Conversation.updated_at.desc()).limit(limit).all()

    # Combine and deduplicate by ID
    all_matches = {str(c.id): c for c in conversations + message_matches}
    results = list(all_matches.values())[:limit]

    return [
        ConversationResponse(
            id=str(c.id),
            title=c.title,
            titleGenerated=c.title_generated,
            createdAt=c.created_at.isoformat(),
            updatedAt=c.updated_at.isoformat(),
            messageCount=c.message_count,
            firstMessage=c.first_message
        )
        for c in results
    ]
