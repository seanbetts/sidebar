"""Operations for memory tool commands."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from api.models.user_memory import UserMemory
from api.services.memory_tools.formatters import format_directory_listing, format_file_view
from api.services.memory_tools.path_utils import normalize_path


def handle_view(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Handle a memory view command for files or directories.

    Args:
        db: Database session.
        user_id: Current user ID.
        payload: Memory tool payload with path and optional view_range.

    Returns:
        Result dict with formatted content or error message.
    """
    path = payload.get("path") or "/memories"
    path = normalize_path(path)
    view_range = payload.get("view_range")
    memories = list_memories(db, user_id)

    if is_file(path, memories):
        memory = get_memory(db, user_id, path)
        if not memory:
            return error(f"The path {path} does not exist. Please provide a valid path.")
        content = format_file_view(path, memory.content, view_range)
        return success({"content": content, "path": path})

    if not is_directory(path, memories):
        return error(f"The path {path} does not exist. Please provide a valid path.")

    listing = format_directory_listing(path, memories)
    return success({"content": listing, "path": path})


def handle_create(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Handle a memory create command.

    Args:
        db: Database session.
        user_id: Current user ID.
        payload: Memory tool payload with path and file_text/content.

    Returns:
        Result dict with success message or error message.
    """
    path = normalize_path(payload.get("path"))
    if path == "/memories":
        return error("Error: File /memories already exists")
    content = payload.get("file_text")
    if content is None:
        content = payload.get("content")
    validate_content(content)

    memories = list_memories(db, user_id)
    if is_file(path, memories) or is_directory(path, memories):
        return error(f"Error: File {path} already exists")

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
    return success({"content": f"File created successfully at: {path}", "path": path})


def handle_str_replace(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Handle a memory string replacement command.

    Args:
        db: Database session.
        user_id: Current user ID.
        payload: Memory tool payload with path, old_str, new_str.

    Returns:
        Result dict with edited content or error message.
    """
    path = normalize_path(payload.get("path"))
    old_str = payload.get("old_str")
    new_str = payload.get("new_str")
    if not isinstance(old_str, str) or not isinstance(new_str, str):
        return error("Error: Invalid replace parameters")

    memory = get_memory(db, user_id, path)
    if not memory:
        return error(
            f"Error: The path {path} does not exist. Please provide a valid path."
        )

    exact_count = memory.content.count(old_str)
    if exact_count == 1:
        updated_content = memory.content.replace(old_str, new_str)
    elif exact_count > 1:
        occurrences = find_occurrences(memory.content, old_str)
        line_list = ", ".join(str(line) for line in sorted(set(occurrences)))
        return error(
            "No replacement was performed. Multiple occurrences of "
            f"old_str `{old_str}` in lines: {line_list}. Please ensure it is unique"
        )
    else:
        fuzzy_matches = find_fuzzy_block_occurrences(memory.content, old_str)
        if not fuzzy_matches:
            return error(
                f"No replacement was performed, old_str `{old_str}` did not appear in {path}."
            )
        if len(fuzzy_matches) > 1:
            line_list = ", ".join(str(line) for line in sorted(set(fuzzy_matches)))
            return error(
                "No replacement was performed. Multiple fuzzy matches of "
                f"old_str `{old_str}` in lines: {line_list}. Please ensure it is unique"
            )
        start_index = fuzzy_matches[0] - 1
        content_lines = memory.content.splitlines(keepends=True)
        old_lines = old_str.splitlines()
        end_index = start_index + len(old_lines)
        trailing = content_lines[end_index - 1] if end_index > 0 else ""
        if trailing.endswith("\r\n") and not new_str.endswith(("\n", "\r\n")):
            new_str = f"{new_str}\r\n"
        elif trailing.endswith("\n") and not new_str.endswith(("\n", "\r\n")):
            new_str = f"{new_str}\n"
        updated_content = "".join(content_lines[:start_index]) + new_str + "".join(
            content_lines[end_index:]
        )
    validate_content(updated_content)
    memory.content = updated_content
    memory.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(memory)
    snippet = format_file_view(path, memory.content, None)
    message = f"The memory file has been edited.\n{snippet}"
    return success({"content": message, "path": path})


def handle_insert(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Handle a memory insert command.

    Args:
        db: Database session.
        user_id: Current user ID.
        payload: Memory tool payload with path, insert_line, insert_text/content.

    Returns:
        Result dict with success message or error message.
    """
    path = normalize_path(payload.get("path"))
    insert_line = payload.get("insert_line")
    insert_text = payload.get("insert_text")
    if insert_text is None:
        insert_text = payload.get("content")
    validate_content(insert_text)

    memory = get_memory(db, user_id, path)
    if not memory:
        return error(f"Error: The path {path} does not exist")

    lines = memory.content.splitlines(keepends=True)
    if not isinstance(insert_line, int):
        return error(
            f"Error: Invalid `insert_line` parameter: {insert_line}. "
            f"It should be within the range of lines of the file: [0, {len(lines)}]"
        )
    if insert_line < 0 or insert_line > len(lines):
        return error(
            f"Error: Invalid `insert_line` parameter: {insert_line}. "
            f"It should be within the range of lines of the file: [0, {len(lines)}]"
        )

    updated = "".join(lines[:insert_line]) + insert_text + "".join(lines[insert_line:])

    validate_content(updated)
    memory.content = updated
    memory.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(memory)
    return success({"content": f"The file {path} has been edited.", "path": path})


def handle_delete(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Handle a memory delete command.

    Args:
        db: Database session.
        user_id: Current user ID.
        payload: Memory tool payload with path.

    Returns:
        Result dict with success message or error message.
    """
    path = normalize_path(payload.get("path"))
    memories = list_memories(db, user_id)
    if not is_file(path, memories) and not is_directory(path, memories):
        return error(f"Error: The path {path} does not exist")

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
    return success({"content": f"Successfully deleted {path}", "path": path})


def handle_rename(db: Session, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Handle a memory rename command.

    Args:
        db: Database session.
        user_id: Current user ID.
        payload: Memory tool payload with old_path and new_path.

    Returns:
        Result dict with success message or error message.
    """
    old_path = normalize_path(payload.get("old_path"))
    new_path = normalize_path(payload.get("new_path"))
    if old_path == "/memories":
        return error("Error: The path /memories does not exist")

    memories = list_memories(db, user_id)
    if not is_file(old_path, memories) and not is_directory(old_path, memories):
        return error(f"Error: The path {old_path} does not exist")
    if is_file(new_path, memories) or is_directory(new_path, memories):
        return error(f"Error: The destination {new_path} already exists")
    if new_path.startswith(f"{old_path}/"):
        return error("Error: The destination cannot be within the source")

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
    return success({"content": f"Successfully renamed {old_path} to {new_path}", "path": new_path})


def validate_content(content: Any) -> None:
    """Validate memory content is a string.

    Args:
        content: Content to validate.

    Raises:
        ValueError: If content is not a string.
    """
    if not isinstance(content, str):
        raise ValueError("Invalid content")


def list_memories(db: Session, user_id: str) -> list[UserMemory]:
    """List all memories for a user.

    Args:
        db: Database session.
        user_id: Current user ID.

    Returns:
        Sorted list of UserMemory records.
    """
    return (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id)
        .order_by(UserMemory.path.asc())
        .all()
    )


def get_memory(db: Session, user_id: str, path: str) -> UserMemory | None:
    """Fetch a memory record by path.

    Args:
        db: Database session.
        user_id: Current user ID.
        path: Normalized memory path.

    Returns:
        Matching UserMemory or None if not found.
    """
    return (
        db.query(UserMemory)
        .filter(UserMemory.user_id == user_id, UserMemory.path == path)
        .first()
    )


def is_file(path: str, memories: list[UserMemory]) -> bool:
    """Return True if the path matches a memory file.

    Args:
        path: Normalized memory path.
        memories: List of UserMemory records.

    Returns:
        True if the path is a file, False otherwise.
    """
    if path == "/memories":
        return False
    return any(memory.path == path for memory in memories)


def is_directory(path: str, memories: list[UserMemory]) -> bool:
    """Return True if the path represents a memory directory.

    Args:
        path: Normalized memory path.
        memories: List of UserMemory records.

    Returns:
        True if the path has children or is /memories.
    """
    if path == "/memories":
        return True
    prefix = f"{path}/"
    return any(memory.path.startswith(prefix) for memory in memories)


def find_occurrences(content: str, old_str: str) -> list[int]:
    """Find line numbers containing an exact substring match.

    Args:
        content: File content to scan.
        old_str: Substring to locate.

    Returns:
        Line numbers (1-indexed) where the substring appears.
    """
    if not old_str:
        return []
    matches: list[int] = []
    start = 0
    while True:
        found = content.find(old_str, start)
        if found == -1:
            break
        line_number = content.count("\n", 0, found) + 1
        matches.append(line_number)
        start = found + max(1, len(old_str))
    return matches


def find_fuzzy_block_occurrences(content: str, old_str: str) -> list[int]:
    """Find line starts where old_str matches after whitespace normalization.

    Args:
        content: File content to scan.
        old_str: Block text to locate.

    Returns:
        Line numbers (1-indexed) where the block matches.
    """
    if not old_str:
        return []
    old_lines = old_str.splitlines()
    if not old_lines:
        return []
    content_lines = content.splitlines()

    def normalize_line(line: str) -> str:
        return " ".join(line.strip().split())

    normalized_old = [normalize_line(line) for line in old_lines]
    normalized_content = [normalize_line(line) for line in content_lines]
    matches: list[int] = []
    for index in range(0, len(normalized_content) - len(normalized_old) + 1):
        if normalized_content[index : index + len(normalized_old)] == normalized_old:
            matches.append(index + 1)
    return matches


def success(data: dict[str, Any]) -> dict[str, Any]:
    """Build a success result payload for memory tool commands.

    Args:
        data: Response payload.

    Returns:
        Success result envelope.
    """
    return {"success": True, "data": data, "error": None}


def error(message: str) -> dict[str, Any]:
    """Build an error result payload for memory tool commands.

    Args:
        message: Error message.

    Returns:
        Error result envelope.
    """
    return {"success": False, "data": None, "error": message}
