"""Memory tool handler for persistent user memory."""
from __future__ import annotations

import re
import urllib.parse
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from api.models.user_memory import UserMemory
from api.security.audit_logger import AuditLogger


class MemoryToolHandler:
    """Execute memory tool commands against user memories."""

    MAX_PATH_LENGTH = 500
    LINE_LIMIT = 999_999
    HIDDEN_PATTERN = re.compile(r"^\.")

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
        except ValueError as exc:
            AuditLogger.log_tool_call(
                tool_name="Memory Tool",
                parameters=payload,
                duration_ms=(datetime.now(timezone.utc) - start).total_seconds() * 1000,
                success=False,
                error=str(exc),
                user_id=user_id,
            )
            return MemoryToolHandler._error(str(exc))
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
        path = payload.get("path") or "/memories"
        path = MemoryToolHandler._normalize_path(path)
        view_range = payload.get("view_range")
        memories = MemoryToolHandler._list_memories(db, user_id)

        if MemoryToolHandler._is_file(path, memories):
            memory = MemoryToolHandler._get_memory(db, user_id, path)
            if not memory:
                return MemoryToolHandler._error(
                    f"The path {path} does not exist. Please provide a valid path."
                )
            content = MemoryToolHandler._format_file_view(path, memory.content, view_range)
            return MemoryToolHandler._success({"content": content, "path": path})

        if not MemoryToolHandler._is_directory(path, memories):
            return MemoryToolHandler._error(
                f"The path {path} does not exist. Please provide a valid path."
            )

        listing = MemoryToolHandler._format_directory_listing(path, memories)
        return MemoryToolHandler._success({"content": listing, "path": path})

    @staticmethod
    def _handle_create(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = MemoryToolHandler._normalize_path(payload.get("path"))
        if path == "/memories":
            return MemoryToolHandler._error("Error: File /memories already exists")
        content = payload.get("file_text")
        if content is None:
            content = payload.get("content")
        MemoryToolHandler._validate_content(content)

        memories = MemoryToolHandler._list_memories(db, user_id)
        if MemoryToolHandler._is_file(path, memories) or MemoryToolHandler._is_directory(path, memories):
            return MemoryToolHandler._error(f"Error: File {path} already exists")

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
        return MemoryToolHandler._success(
            {"content": f"File created successfully at: {path}", "path": path}
        )

    @staticmethod
    def _handle_str_replace(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = MemoryToolHandler._normalize_path(payload.get("path"))
        old_str = payload.get("old_str")
        new_str = payload.get("new_str")
        if not isinstance(old_str, str) or not isinstance(new_str, str):
            return MemoryToolHandler._error("Error: Invalid replace parameters")

        memory = MemoryToolHandler._get_memory(db, user_id, path)
        if not memory:
            return MemoryToolHandler._error(
                f"Error: The path {path} does not exist. Please provide a valid path."
            )

        occurrences = MemoryToolHandler._find_occurrences(memory.content, old_str)
        if not occurrences:
            return MemoryToolHandler._error(
                f"No replacement was performed, old_str `{old_str}` did not appear verbatim in {path}."
            )
        if len(occurrences) > 1:
            line_list = ", ".join(str(line) for line in sorted(set(occurrences)))
            return MemoryToolHandler._error(
                "No replacement was performed. Multiple occurrences of "
                f"old_str `{old_str}` in lines: {line_list}. Please ensure it is unique"
            )

        updated_content = memory.content.replace(old_str, new_str)
        MemoryToolHandler._validate_content(updated_content)
        memory.content = updated_content
        memory.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(memory)
        snippet = MemoryToolHandler._format_file_view(path, memory.content, None)
        message = f"The memory file has been edited.\n{snippet}"
        return MemoryToolHandler._success({"content": message, "path": path})

    @staticmethod
    def _handle_insert(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = MemoryToolHandler._normalize_path(payload.get("path"))
        insert_line = payload.get("insert_line")
        insert_text = payload.get("insert_text")
        if insert_text is None:
            insert_text = payload.get("content")
        MemoryToolHandler._validate_content(insert_text)

        memory = MemoryToolHandler._get_memory(db, user_id, path)
        if not memory:
            return MemoryToolHandler._error(f"Error: The path {path} does not exist")

        lines = memory.content.splitlines(keepends=True)
        if not isinstance(insert_line, int):
            return MemoryToolHandler._error(
                f"Error: Invalid `insert_line` parameter: {insert_line}. "
                f"It should be within the range of lines of the file: [0, {len(lines)}]"
            )
        if insert_line < 0 or insert_line > len(lines):
            return MemoryToolHandler._error(
                f"Error: Invalid `insert_line` parameter: {insert_line}. "
                f"It should be within the range of lines of the file: [0, {len(lines)}]"
            )

        updated = "".join(lines[:insert_line]) + insert_text + "".join(lines[insert_line:])

        MemoryToolHandler._validate_content(updated)
        memory.content = updated
        memory.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(memory)
        return MemoryToolHandler._success(
            {"content": f"The file {path} has been edited.", "path": path}
        )

    @staticmethod
    def _handle_delete(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        path = MemoryToolHandler._normalize_path(payload.get("path"))
        memories = MemoryToolHandler._list_memories(db, user_id)
        if not MemoryToolHandler._is_file(path, memories) and not MemoryToolHandler._is_directory(path, memories):
            return MemoryToolHandler._error(f"Error: The path {path} does not exist")

        if path == "/memories":
            targets = memories
        else:
            targets = [
                memory
                for memory in memories
                if memory.path == path or memory.path.startswith(f"{path}/")
            ]
        for memory in targets:
            db.delete(memory)
        db.commit()
        return MemoryToolHandler._success(
            {"content": f"Successfully deleted {path}", "path": path}
        )

    @staticmethod
    def _handle_rename(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        old_path = MemoryToolHandler._normalize_path(payload.get("old_path"))
        new_path = MemoryToolHandler._normalize_path(payload.get("new_path"))
        if old_path == "/memories":
            return MemoryToolHandler._error("Error: The path /memories does not exist")

        memories = MemoryToolHandler._list_memories(db, user_id)
        if not MemoryToolHandler._is_file(old_path, memories) and not MemoryToolHandler._is_directory(old_path, memories):
            return MemoryToolHandler._error(f"Error: The path {old_path} does not exist")
        if MemoryToolHandler._is_file(new_path, memories) or MemoryToolHandler._is_directory(new_path, memories):
            return MemoryToolHandler._error(f"Error: The destination {new_path} already exists")
        if new_path.startswith(f"{old_path}/"):
            return MemoryToolHandler._error("Error: The destination cannot be within the source")

        updated_at = datetime.now(timezone.utc)
        targets = [
            memory
            for memory in memories
            if memory.path == old_path or memory.path.startswith(f"{old_path}/")
        ]
        for memory in targets:
            suffix = memory.path[len(old_path):]
            memory.path = f"{new_path}{suffix}"
            memory.updated_at = updated_at
        db.commit()
        return MemoryToolHandler._success(
            {"content": f"Successfully renamed {old_path} to {new_path}", "path": new_path}
        )

    @staticmethod
    def _normalize_path(path: Any) -> str:
        if not isinstance(path, str):
            raise ValueError("Invalid path")
        path = path.strip()
        if len(path) > MemoryToolHandler.MAX_PATH_LENGTH:
            raise ValueError("Path too long")
        if "\\" in path:
            raise ValueError("Invalid path")
        if any(ord(ch) < 32 for ch in path):
            raise ValueError("Invalid path")
        if path.endswith("/") and path != "/memories":
            path = path.rstrip("/")
        if not path.startswith("/memories"):
            if path == "memories":
                path = "/memories"
            elif path.startswith("memories/"):
                path = f"/{path}"
            else:
                path = f"/memories/{path.lstrip('/')}"
        if path != "/memories" and not path.startswith("/memories/"):
            raise ValueError("Invalid path")
        if ".." in path or "//" in path:
            raise ValueError("Invalid path")
        if "%" in path:
            decoded = urllib.parse.unquote(path)
            if ".." in decoded or "\\" in decoded:
                raise ValueError("Invalid path")
        if path == "/memories":
            return path
        parts = path[len("/memories/"):].split("/")
        for part in parts:
            if part in {"", ".", ".."}:
                raise ValueError("Invalid path")
        return path

    @staticmethod
    def _validate_content(content: Any) -> None:
        if not isinstance(content, str):
            raise ValueError("Invalid content")

    @staticmethod
    def _list_memories(db: Session, user_id: str) -> list[UserMemory]:
        return (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id)
            .order_by(UserMemory.path.asc())
            .all()
        )

    @staticmethod
    def _get_memory(db: Session, user_id: str, path: str) -> UserMemory | None:
        return (
            db.query(UserMemory)
            .filter(UserMemory.user_id == user_id, UserMemory.path == path)
            .first()
        )

    @staticmethod
    def _is_file(path: str, memories: list[UserMemory]) -> bool:
        if path == "/memories":
            return False
        return any(memory.path == path for memory in memories)

    @staticmethod
    def _is_directory(path: str, memories: list[UserMemory]) -> bool:
        if path == "/memories":
            return True
        prefix = f"{path}/"
        return any(memory.path.startswith(prefix) for memory in memories)

    @staticmethod
    def _find_occurrences(content: str, old_str: str) -> list[int]:
        if not old_str:
            return []
        lines = content.splitlines()
        matches = []
        for index, line in enumerate(lines, start=1):
            start = 0
            while True:
                found = line.find(old_str, start)
                if found == -1:
                    break
                matches.append(index)
                start = found + max(1, len(old_str))
        return matches

    @staticmethod
    def _format_file_view(path: str, content: str, view_range: Any) -> str:
        lines = content.splitlines()
        if len(lines) > MemoryToolHandler.LINE_LIMIT:
            raise ValueError(
                f"File {path} exceeds maximum line limit of {MemoryToolHandler.LINE_LIMIT:,} lines."
            )
        start = 1
        end = len(lines)
        if view_range is not None:
            if (
                not isinstance(view_range, (list, tuple))
                or len(view_range) != 2
                or not all(isinstance(value, int) for value in view_range)
            ):
                raise ValueError("Error: Invalid view_range parameter.")
            start, end = view_range
            if start < 1:
                start = 1
            if end > len(lines):
                end = len(lines)
            if start > end:
                raise ValueError("Error: Invalid view_range parameter.")
        header = f"Here's the content of {path} with line numbers:"
        output_lines = [header]
        for line_number in range(start, end + 1):
            line = lines[line_number - 1]
            output_lines.append(f"{line_number:6d}\t{line}")
        return "\n".join(output_lines)

    @staticmethod
    def _format_directory_listing(path: str, memories: list[UserMemory]) -> str:
        visible_memories = [
            memory
            for memory in memories
            if MemoryToolHandler._is_visible_path(memory.path)
        ]
        base_size = MemoryToolHandler._directory_size(path, visible_memories)
        header = (
            "Here're the files and directories up to 2 levels deep in "
            f"{path}, excluding hidden items and node_modules:"
        )
        entries = [(path, base_size)]

        for memory in visible_memories:
            if not memory.path.startswith(f"{path}/"):
                continue
            relative = memory.path[len(path) + 1:]
            parts = relative.split("/")
            if len(parts) <= 2:
                entries.append((memory.path, MemoryToolHandler._content_size(memory.content)))
            for depth in range(1, min(2, len(parts)) + 1):
                dir_path = f"{path}/{'/'.join(parts[:depth])}"
                entries.append((dir_path, MemoryToolHandler._directory_size(dir_path, visible_memories)))

        unique_entries = {}
        for entry_path, size in entries:
            unique_entries[entry_path] = max(unique_entries.get(entry_path, 0), size)

        lines = [header]
        for entry_path in sorted(unique_entries.keys()):
            size = unique_entries[entry_path]
            lines.append(f"{MemoryToolHandler._format_size(size)}\t{entry_path}")
        return "\n".join(lines)

    @staticmethod
    def _is_visible_path(path: str) -> bool:
        if not path.startswith("/memories"):
            return False
        parts = path[len("/memories"):].split("/")
        for part in parts:
            if part in {"", "."}:
                continue
            if part == "node_modules":
                return False
            if MemoryToolHandler.HIDDEN_PATTERN.match(part):
                return False
        return True

    @staticmethod
    def _directory_size(path: str, memories: list[UserMemory]) -> int:
        if path == "/memories":
            prefix = "/memories/"
        else:
            prefix = f"{path}/"
        return sum(
            MemoryToolHandler._content_size(memory.content)
            for memory in memories
            if memory.path == path or memory.path.startswith(prefix)
        )

    @staticmethod
    def _content_size(content: str) -> int:
        return len(content.encode("utf-8"))

    @staticmethod
    def _format_size(size: int) -> str:
        if size < 1024:
            return f"{size}B"
        units = ["K", "M", "G", "T"]
        value = float(size)
        unit_index = -1
        while value >= 1024 and unit_index < len(units) - 1:
            value /= 1024
            unit_index += 1
        return f"{value:.1f}{units[unit_index]}"

    @staticmethod
    def _success(data: dict[str, Any]) -> dict[str, Any]:
        return {"success": True, "data": data, "error": None}

    @staticmethod
    def _error(message: str) -> dict[str, Any]:
        return {"success": False, "data": None, "error": message}
