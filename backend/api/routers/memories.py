"""Memories API router."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.memory_service import MemoryService

router = APIRouter(prefix="/memories", tags=["memories"])


class MemoryResponse(BaseModel):
    """Response payload for a memory record."""

    id: str
    path: str
    content: str
    created_at: str
    updated_at: str


class MemoryCreate(BaseModel):
    """Request payload for creating a memory record."""

    path: str
    content: str


class MemoryUpdate(BaseModel):
    """Request payload for updating a memory record."""

    path: str | None = None
    content: str | None = None


@router.get("", response_model=list[MemoryResponse])
async def list_memories(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """List all memories for the current user.

    Args:
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        List of memory records for the user.
    """
    memories = MemoryService.list_memories(db, user_id)
    return [
        MemoryResponse(
            id=str(memory.id),
            path=memory.path,
            content=memory.content,
            created_at=memory.created_at.isoformat(),
            updated_at=memory.updated_at.isoformat(),
        )
        for memory in memories
    ]


@router.get("/{memory_id}", response_model=MemoryResponse)
async def get_memory(
    memory_id: UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Fetch a single memory by ID.

    Args:
        memory_id: Memory UUID.
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Memory record if found.

    Raises:
        NotFoundError: If memory is not found.
    """
    memory = MemoryService.get_memory(db, user_id, memory_id)
    return MemoryResponse(
        id=str(memory.id),
        path=memory.path,
        content=memory.content,
        created_at=memory.created_at.isoformat(),
        updated_at=memory.updated_at.isoformat(),
    )


@router.post("", response_model=MemoryResponse)
async def create_memory(
    payload: MemoryCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Create a new memory record.

    Args:
        payload: Memory create payload.
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Created memory record.

    Raises:
        BadRequestError: For invalid path/content.
        ConflictError: If duplicate exists.
    """
    memory = MemoryService.create_memory(db, user_id, payload.path, payload.content)
    return MemoryResponse(
        id=str(memory.id),
        path=memory.path,
        content=memory.content,
        created_at=memory.created_at.isoformat(),
        updated_at=memory.updated_at.isoformat(),
    )


@router.patch("/{memory_id}", response_model=MemoryResponse)
async def update_memory(
    memory_id: UUID,
    payload: MemoryUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Update a memory record by ID.

    Args:
        memory_id: Memory UUID.
        payload: Memory update payload.
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Updated memory record.

    Raises:
        BadRequestError: For invalid path/content.
        NotFoundError: If memory is not found.
        ConflictError: If path conflicts.
    """
    memory = MemoryService.update_memory(
        db,
        user_id,
        memory_id,
        path=payload.path,
        content=payload.content,
    )
    return MemoryResponse(
        id=str(memory.id),
        path=memory.path,
        content=memory.content,
        created_at=memory.created_at.isoformat(),
        updated_at=memory.updated_at.isoformat(),
    )


@router.delete("/{memory_id}")
async def delete_memory(
    memory_id: UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Delete a memory record by ID.

    Args:
        memory_id: Memory UUID.
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Success flag.

    Raises:
        NotFoundError: If memory is not found.
    """
    MemoryService.delete_memory(db, user_id, memory_id)
    return {"success": True}
