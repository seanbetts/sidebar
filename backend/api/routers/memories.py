"""Memories API router."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.models.user_memory import UserMemory
from api.services.memory_tools.path_utils import normalize_path
from api.services.memory_tools.operations import validate_content


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

    path: Optional[str] = None
    content: Optional[str] = None


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
    memories = (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id)
        .order_by(UserMemory.path.asc())
        .all()
    )
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
        HTTPException: 404 if memory is not found.
    """
    memory = (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id, UserMemory.id == memory_id)
        .first()
    )
    if not memory:
        raise HTTPException(status_code=404, detail="Memory not found")
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
        HTTPException: 400 for invalid path/content, 409 if duplicate exists.
    """
    try:
        normalized_path = normalize_path(payload.path)
        validate_content(payload.content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    existing = (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id, UserMemory.path == normalized_path)
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="Memory already exists")

    now = datetime.now(timezone.utc)
    memory = UserMemory(
        user_id=user_id,
        path=normalized_path,
        content=payload.content,
        created_at=now,
        updated_at=now,
    )
    db.add(memory)
    db.commit()
    db.refresh(memory)
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
        HTTPException: 400 for invalid path/content, 404 if not found,
            409 if path conflicts.
    """
    memory = (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id, UserMemory.id == memory_id)
        .first()
    )
    if not memory:
        raise HTTPException(status_code=404, detail="Memory not found")

    if payload.path is not None:
        try:
            normalized_path = normalize_path(payload.path)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if normalized_path != memory.path:
            conflict = (
                db.query(UserMemory)
                .filter(UserMemory.user_id == user_id, UserMemory.path == normalized_path)
                .first()
            )
            if conflict:
                raise HTTPException(status_code=409, detail="Memory already exists")
            memory.path = normalized_path

    if payload.content is not None:
        try:
            validate_content(payload.content)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        memory.content = payload.content

    memory.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(memory)
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
        HTTPException: 404 if memory is not found.
    """
    memory = (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id, UserMemory.id == memory_id)
        .first()
    )
    if not memory:
        raise HTTPException(status_code=404, detail="Memory not found")
    db.delete(memory)
    db.commit()
    return {"success": True}
