"""Memory service for shared memory business logic."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy.orm import Session

from api.exceptions import BadRequestError, ConflictError, NotFoundError
from api.models.user_memory import UserMemory
from api.services.memory_tools.operations import validate_content
from api.services.memory_tools.path_utils import normalize_path


class MemoryService:
    """Service layer for memory operations."""

    @staticmethod
    def list_memories(db: Session, user_id: str) -> list[UserMemory]:
        """List all memories for a user.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            List of memory records.
        """
        return (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id)
            .order_by(UserMemory.path.asc())
            .all()
        )

    @staticmethod
    def get_memory(db: Session, user_id: str, memory_id: UUID) -> UserMemory:
        """Fetch a memory record by ID.

        Args:
            db: Database session.
            user_id: Current user ID.
            memory_id: Memory UUID.

        Returns:
            Memory record.

        Raises:
            NotFoundError: If no memory matches.
        """
        memory = (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id, UserMemory.id == memory_id)
            .first()
        )
        if not memory:
            raise NotFoundError("Memory", str(memory_id))
        return memory

    @staticmethod
    def create_memory(db: Session, user_id: str, path: str, content: str) -> UserMemory:
        """Create a new memory record.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Memory path.
            content: Memory content.

        Returns:
            Created memory record.
        """
        try:
            normalized_path = normalize_path(path)
            validate_content(content)
        except ValueError as exc:
            raise BadRequestError(str(exc)) from exc

        existing = (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id, UserMemory.path == normalized_path)
            .first()
        )
        if existing:
            raise ConflictError("Memory already exists")

        now = datetime.now(UTC)
        memory = UserMemory(
            user_id=user_id,
            path=normalized_path,
            content=content,
            created_at=now,
            updated_at=now,
        )
        db.add(memory)
        db.commit()
        db.refresh(memory)
        return memory

    @staticmethod
    def update_memory(
        db: Session,
        user_id: str,
        memory_id: UUID,
        *,
        path: str | None = None,
        content: str | None = None,
    ) -> UserMemory:
        """Update a memory record.

        Args:
            db: Database session.
            user_id: Current user ID.
            memory_id: Memory UUID.
            path: Optional new path.
            content: Optional new content.

        Returns:
            Updated memory record.
        """
        memory = MemoryService.get_memory(db, user_id, memory_id)

        if path is not None:
            try:
                normalized_path = normalize_path(path)
            except ValueError as exc:
                raise BadRequestError(str(exc)) from exc
            if normalized_path != memory.path:
                conflict = (
                    db.query(UserMemory)
                    .filter(
                        UserMemory.user_id == user_id,
                        UserMemory.path == normalized_path,
                    )
                    .first()
                )
                if conflict:
                    raise ConflictError("Memory already exists")
                memory.path = normalized_path

        if content is not None:
            try:
                validate_content(content)
            except ValueError as exc:
                raise BadRequestError(str(exc)) from exc
            memory.content = content

        memory.updated_at = datetime.now(UTC)
        db.commit()
        db.refresh(memory)
        return memory

    @staticmethod
    def delete_memory(db: Session, user_id: str, memory_id: UUID) -> None:
        """Delete a memory record.

        Args:
            db: Database session.
            user_id: Current user ID.
            memory_id: Memory UUID.

        Raises:
            NotFoundError: If no memory matches.
        """
        memory = MemoryService.get_memory(db, user_id, memory_id)
        db.delete(memory)
        db.commit()
