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
from api.services.memory_tool_handler import MemoryToolHandler


router = APIRouter(prefix="/memories", tags=["memories"])


class MemoryResponse(BaseModel):
    id: str
    path: str
    content: str
    created_at: str
    updated_at: str


class MemoryCreate(BaseModel):
    path: str
    content: str


class MemoryUpdate(BaseModel):
    path: Optional[str] = None
    content: Optional[str] = None


@router.get("", response_model=list[MemoryResponse])
async def list_memories(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
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
    MemoryToolHandler._validate_path(payload.path)
    MemoryToolHandler._validate_content(payload.content)
    existing = (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id, UserMemory.path == payload.path)
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="Memory already exists")

    now = datetime.now(timezone.utc)
    memory = UserMemory(
        user_id=user_id,
        path=payload.path,
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
    memory = (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id, UserMemory.id == memory_id)
        .first()
    )
    if not memory:
        raise HTTPException(status_code=404, detail="Memory not found")

    if payload.path is not None:
        MemoryToolHandler._validate_path(payload.path)
        if payload.path != memory.path:
            conflict = (
                db.query(UserMemory)
                .filter(UserMemory.user_id == user_id, UserMemory.path == payload.path)
                .first()
            )
            if conflict:
                raise HTTPException(status_code=409, detail="Memory already exists")
            memory.path = payload.path

    if payload.content is not None:
        MemoryToolHandler._validate_content(payload.content)
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
