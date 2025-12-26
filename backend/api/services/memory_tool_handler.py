"""Memory tool handler for persistent user memory."""
from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from api.models.user_memory import UserMemory
from api.security.audit_logger import AuditLogger


class MemoryToolHandler:
    """Execute memory tool commands against user memories."""

    MAX_CONTENT_BYTES = 100 * 1024
    MAX_PATH_LENGTH = 500
    PATH_PATTERN = re.compile(r"^/memories/[a-zA-Z0-9_/-]+\.md$")

    @staticmethod
    def execute_command(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        start = datetime.now(timezone.utc)
        command = (payload.get("command") or "").strip()
        try:
            if command == "view":
                result = MemoryToolHandler._handle_view(db, user_id, payload)
            elif command == "create":
                result = MemoryToolHandler._handle_create(db, user_id, payload)
            elif command == "str_replace":
                result = MemoryToolHandler._handle_str_replace(db, user_id, payload)
            elif command == "insert":
                result = MemoryToolHandler._handle_insert(db, user_id, payload)
            elif command == "delete":
                result = MemoryToolHandler._handle_delete(db, user_id, payload)
            elif command == "rename":
                result = MemoryToolHandler._handle_rename(db, user_id, payload)
            else:
                return MemoryToolHandler._error("Invalid command")

            AuditLogger.log_tool_call(
                tool_name="Memory Tool",
                parameters=payload,
                duration_ms=(datetime.now(timezone.utc) - start).total_seconds() * 1000,
                success=result.get("success", False),
                error=result.get("error"),
                user_id=user_id,
            )
            if result.get("success") and isinstance(result.get("data"), dict):
                result["data"]["command"] = command
            return result
        except Exception as exc:
            AuditLogger.log_tool_call(
                tool_name="Memory Tool",
                parameters=payload,
                duration_ms=(datetime.now(timezone.utc) - start).total_seconds() * 1000,
                success=False,
                error=str(exc),
                user_id=user_id,
            )
            return MemoryToolHandler._error("Memory tool failed")

    @staticmethod
    def get_all_memories_for_prompt(db: Session, user_id: str) -> list[dict[str, str]]:
        memories = (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id)
            .order_by(UserMemory.path.asc())
            .all()
        )
        return [{"path": memory.path, "content": memory.content} for memory in memories]

    @staticmethod
    def build_memory_block(memories: list[dict[str, str]]) -> str:
        if not memories:
            return "<memory>\nNo stored memories.\n</memory>"
        lines = ["<memory>", "The following entries are persistent user memories:"]
        for memory in memories:
            path = memory.get("path", "unknown")
            content = memory.get("content", "")
            lines.append(f"\n[path: {path}]\n{content}")
        lines.append("</memory>")
        return "\n".join(lines)

    @staticmethod
    def _handle_view(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = payload.get("path")
        if path:
            MemoryToolHandler._validate_path(path)
            memory = MemoryToolHandler._get_memory(db, user_id, path)
            if not memory:
                return MemoryToolHandler._error("Memory not found")
            return MemoryToolHandler._success(
                {"path": memory.path, "content": memory.content}
            )

        memories = MemoryToolHandler.get_all_memories_for_prompt(db, user_id)
        return MemoryToolHandler._success({"items": memories})

    @staticmethod
    def _handle_create(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = payload.get("path")
        content = payload.get("content")
        MemoryToolHandler._validate_path(path)
        MemoryToolHandler._validate_content(content)

        existing = MemoryToolHandler._get_memory(db, user_id, path)
        if existing:
            return MemoryToolHandler._error("Memory already exists")

        now = datetime.now(timezone.utc)
        memory = UserMemory(
            user_id=user_id,
            path=path,
            content=content,
            created_at=now,
            updated_at=now,
        )
        db.add(memory)
        db.commit()
        db.refresh(memory)
        return MemoryToolHandler._success({"path": memory.path, "content": memory.content})

    @staticmethod
    def _handle_str_replace(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = payload.get("path")
        old_str = payload.get("old_str")
        new_str = payload.get("new_str")
        MemoryToolHandler._validate_path(path)
        if not isinstance(old_str, str) or not isinstance(new_str, str):
            return MemoryToolHandler._error("Invalid replace parameters")

        memory = MemoryToolHandler._get_memory(db, user_id, path)
        if not memory:
            return MemoryToolHandler._error("Memory not found")

        occurrences = memory.content.count(old_str)
        if occurrences == 0:
            return MemoryToolHandler._error("Old string not found")
        if occurrences > 1:
            return MemoryToolHandler._error("Old string is not unique")

        updated_content = memory.content.replace(old_str, new_str)
        MemoryToolHandler._validate_content(updated_content)
        memory.content = updated_content
        memory.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(memory)
        return MemoryToolHandler._success({"path": memory.path, "content": memory.content})

    @staticmethod
    def _handle_insert(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = payload.get("path")
        content = payload.get("content")
        position = payload.get("position")
        MemoryToolHandler._validate_path(path)
        MemoryToolHandler._validate_content(content)
        if position not in {"start", "end"}:
            return MemoryToolHandler._error("Invalid insert position")

        memory = MemoryToolHandler._get_memory(db, user_id, path)
        if not memory:
            return MemoryToolHandler._error("Memory not found")

        if position == "start":
            updated = MemoryToolHandler._merge_text(content, memory.content)
        else:
            updated = MemoryToolHandler._merge_text(memory.content, content)

        MemoryToolHandler._validate_content(updated)
        memory.content = updated
        memory.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(memory)
        return MemoryToolHandler._success({"path": memory.path, "content": memory.content})

    @staticmethod
    def _handle_delete(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = payload.get("path")
        MemoryToolHandler._validate_path(path)
        memory = MemoryToolHandler._get_memory(db, user_id, path)
        if not memory:
            return MemoryToolHandler._error("Memory not found")
        db.delete(memory)
        db.commit()
        return MemoryToolHandler._success({"path": path})

    @staticmethod
    def _handle_rename(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        old_path = payload.get("old_path")
        new_path = payload.get("new_path")
        MemoryToolHandler._validate_path(old_path)
        MemoryToolHandler._validate_path(new_path)

        memory = MemoryToolHandler._get_memory(db, user_id, old_path)
        if not memory:
            return MemoryToolHandler._error("Memory not found")
        if MemoryToolHandler._get_memory(db, user_id, new_path):
            return MemoryToolHandler._error("Destination already exists")

        memory.path = new_path
        memory.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(memory)
        return MemoryToolHandler._success({"path": memory.path, "content": memory.content})

    @staticmethod
    def _validate_path(path: Any) -> None:
        if not isinstance(path, str):
            raise ValueError("Invalid path")
        if len(path) > MemoryToolHandler.MAX_PATH_LENGTH:
            raise ValueError("Path too long")
        if ".." in path or "//" in path:
            raise ValueError("Invalid path")
        if not MemoryToolHandler.PATH_PATTERN.match(path):
            raise ValueError("Invalid path format")

    @staticmethod
    def _validate_content(content: Any) -> None:
        if not isinstance(content, str):
            raise ValueError("Invalid content")
        if len(content.encode("utf-8")) > MemoryToolHandler.MAX_CONTENT_BYTES:
            raise ValueError("Content too large")

    @staticmethod
    def _get_memory(db: Session, user_id: str, path: str) -> UserMemory | None:
        return (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id, UserMemory.path == path)
            .first()
        )

    @staticmethod
    def _merge_text(first: str, second: str) -> str:
        if not first:
            return second
        if not second:
            return first
        if first.endswith("\n") or second.startswith("\n"):
            return f"{first}{second}"
        return f"{first}\n{second}"

    @staticmethod
    def _success(data: dict[str, Any]) -> dict[str, Any]:
        return {"success": True, "data": data, "error": None}

    @staticmethod
    def _error(message: str) -> dict[str, Any]:
        return {"success": False, "data": None, "error": message}
