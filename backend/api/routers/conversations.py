"""Conversations API router with JSONB message storage."""
# ruff: noqa: B008, N815

from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.conversation_service import ConversationService


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


def _conversation_response(conversation) -> ConversationResponse:
    return ConversationResponse(
        id=str(conversation.id),
        title=conversation.title,
        titleGenerated=conversation.title_generated,
        createdAt=conversation.created_at.isoformat(),
        updatedAt=conversation.updated_at.isoformat(),
        messageCount=conversation.message_count,
        firstMessage=conversation.first_message,
    )


@router.post("", response_model=ConversationResponse)
@router.post("/", response_model=ConversationResponse)
def create_conversation(
    data: ConversationCreate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Create a new conversation."""
    conversation = ConversationService.create_conversation(db, user_id, data.title)

    return _conversation_response(conversation)


@router.get("", response_model=list[ConversationResponse])
@router.get("/", response_model=list[ConversationResponse])
def list_conversations(
    user_id: str = Depends(get_current_user_id), db: Session = Depends(get_db)
):
    """List all conversations for the current user."""
    conversations = ConversationService.list_conversations(db, user_id)

    return [_conversation_response(c) for c in conversations]


@router.get("/{conversation_id}", response_model=ConversationWithMessages)
def get_conversation(
    conversation_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Get a single conversation with all messages."""
    conversation = ConversationService.get_conversation(db, user_id, conversation_id)

    return ConversationWithMessages(
        id=str(conversation.id),
        title=conversation.title,
        titleGenerated=conversation.title_generated,
        createdAt=conversation.created_at.isoformat(),
        updatedAt=conversation.updated_at.isoformat(),
        messageCount=conversation.message_count,
        firstMessage=conversation.first_message,
        messages=conversation.messages or [],
    )


@router.post("/{conversation_id}/messages", response_model=ConversationResponse)
def add_message(
    conversation_id: UUID,
    message: MessageCreate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Add a message to a conversation."""
    conversation = ConversationService.add_message(
        db,
        user_id,
        conversation_id,
        message.model_dump(),
    )

    return _conversation_response(conversation)


@router.put("/{conversation_id}", response_model=ConversationResponse)
def update_conversation(
    conversation_id: UUID,
    updates: ConversationUpdate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Update conversation metadata."""
    conversation = ConversationService.update_conversation(
        db,
        user_id,
        conversation_id,
        title=updates.title,
        title_generated=updates.titleGenerated,
        is_archived=updates.isArchived,
    )

    return _conversation_response(conversation)


@router.delete("/{conversation_id}", response_model=ConversationResponse)
def delete_conversation(
    conversation_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Archive (soft delete) a conversation."""
    conversation = ConversationService.update_conversation(
        db,
        user_id,
        conversation_id,
        is_archived=True,
    )

    return _conversation_response(conversation)


@router.post("/search", response_model=list[ConversationResponse])
def search_conversations(
    query: str,
    limit: int = 10,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Full-text search across conversations and messages."""
    results = ConversationService.search_conversations(db, user_id, query, limit=limit)

    return [
        ConversationResponse(
            id=str(c.id),
            title=c.title,
            titleGenerated=c.title_generated,
            createdAt=c.created_at.isoformat(),
            updatedAt=c.updated_at.isoformat(),
            messageCount=c.message_count,
            firstMessage=c.first_message,
        )
        for c in results
    ]
