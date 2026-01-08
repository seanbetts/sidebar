"""Memory tool handler for persistent user memory."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy.orm import Session

from api.models.user_memory import UserMemory
from api.security.audit_logger import AuditLogger
from api.services.memory_tools import operations


class MemoryToolHandler:
    """Execute memory tool commands against user memories."""

    @staticmethod
    def execute_command(
        db: Session, user_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        """Execute a memory tool command and log the result.

        Args:
            db: Database session.
            user_id: Current user ID.
            payload: Tool payload containing command and inputs.

        Returns:
            Normalized tool result payload.
        """
        start = datetime.now(UTC)
        command = (payload.get("command") or "").strip()
        try:
            if command == "view":
                result = operations.handle_view(db, user_id, payload)
            elif command == "create":
                result = operations.handle_create(db, user_id, payload)
            elif command == "str_replace":
                result = operations.handle_str_replace(db, user_id, payload)
            elif command == "insert":
                result = operations.handle_insert(db, user_id, payload)
            elif command == "delete":
                result = operations.handle_delete(db, user_id, payload)
            elif command == "rename":
                result = operations.handle_rename(db, user_id, payload)
            else:
                return operations.error("Invalid command")

            AuditLogger.log_tool_call(
                tool_name="Memory Tool",
                parameters=payload,
                duration_ms=(datetime.now(UTC) - start).total_seconds() * 1000,
                success=result.get("success", False),
                error=result.get("error"),
                user_id=user_id,
            )
            if result.get("success") and isinstance(result.get("data"), dict):
                result["data"]["command"] = command
            return result
        except ValueError as exc:
            AuditLogger.log_tool_call(
                tool_name="Memory Tool",
                parameters=payload,
                duration_ms=(datetime.now(UTC) - start).total_seconds() * 1000,
                success=False,
                error=str(exc),
                user_id=user_id,
            )
            return operations.error(str(exc))
        except Exception as exc:
            AuditLogger.log_tool_call(
                tool_name="Memory Tool",
                parameters=payload,
                duration_ms=(datetime.now(UTC) - start).total_seconds() * 1000,
                success=False,
                error=str(exc),
                user_id=user_id,
            )
            return operations.error("Memory tool failed")

    @staticmethod
    def get_all_memories_for_prompt(db: Session, user_id: str) -> list[dict[str, str]]:
        """Fetch all memories for prompt injection.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            List of memory dicts with path and content.
        """
        memories = (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id)
            .order_by(UserMemory.path.asc())
            .all()
        )
        return [{"path": memory.path, "content": memory.content} for memory in memories]

    @staticmethod
    def build_memory_block(memories: list[dict[str, str]]) -> str:
        """Build a memory block string for prompt inclusion.

        Args:
            memories: Memory entries with path and content.

        Returns:
            Formatted memory block string.
        """
        if not memories:
            return "<memory>\nNo stored memories.\n</memory>"
        lines = ["<memory>", "The following entries are persistent user memories:"]
        for memory in memories:
            path = memory.get("path", "unknown")
            content = memory.get("content", "")
            lines.append(f"\n[path: {path}]\n{content}")
        lines.append("</memory>")
        return "\n".join(lines)
