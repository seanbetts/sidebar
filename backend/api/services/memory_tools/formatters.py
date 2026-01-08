"""Formatters for memory tool output."""

from __future__ import annotations

from typing import Any

from api.models.user_memory import UserMemory
from api.services.memory_tools.constants import LINE_LIMIT
from api.services.memory_tools.path_utils import is_visible_path


def format_file_view(path: str, content: str, view_range: Any) -> str:
    """Format file content with line numbers.

    Args:
        path: Memory file path.
        content: File content.
        view_range: Optional [start, end] line range.

    Returns:
        Formatted string with line numbers.

    Raises:
        ValueError: If the file exceeds the line limit or view_range is invalid.
    """
    lines = content.splitlines()
    if len(lines) > LINE_LIMIT:
        raise ValueError(
            f"File {path} exceeds maximum line limit of {LINE_LIMIT:,} lines."
        )
    start = 1
    end = len(lines)
    if view_range is not None:
        if (
            not isinstance(view_range, list | tuple)
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


def format_directory_listing(path: str, memories: list[UserMemory]) -> str:
    """Format a directory listing for memory paths.

    Args:
        path: Base directory path.
        memories: Memory records to include.

    Returns:
        Formatted directory listing string.
    """
    visible_memories = [memory for memory in memories if is_visible_path(memory.path)]
    base_size = directory_size(path, visible_memories)
    header = (
        "Here're the files and directories up to 2 levels deep in "
        f"{path}, excluding hidden items and node_modules:"
    )
    entries = [(path, base_size)]

    for memory in visible_memories:
        if not memory.path.startswith(f"{path}/"):
            continue
        relative = memory.path[len(path) + 1 :]
        parts = relative.split("/")
        if len(parts) <= 2:
            entries.append((memory.path, content_size(memory.content)))
        for depth in range(1, min(2, len(parts)) + 1):
            dir_path = f"{path}/{'/'.join(parts[:depth])}"
            entries.append((dir_path, directory_size(dir_path, visible_memories)))

    unique_entries: dict[str, int] = {}
    for entry_path, size in entries:
        unique_entries[entry_path] = max(unique_entries.get(entry_path, 0), size)

    lines = [header]
    for entry_path in sorted(unique_entries.keys()):
        size = unique_entries[entry_path]
        lines.append(f"{format_size(size)}\t{entry_path}")
    return "\n".join(lines)


def directory_size(path: str, memories: list[UserMemory]) -> int:
    """Compute the total size for a directory path.

    Args:
        path: Directory path.
        memories: Memory records to include.

    Returns:
        Total size in bytes.
    """
    prefix = "/memories/" if path == "/memories" else f"{path}/"
    return sum(
        content_size(memory.content)
        for memory in memories
        if memory.path == path or memory.path.startswith(prefix)
    )


def content_size(content: str) -> int:
    """Return the UTF-8 byte size of content."""
    return len(content.encode("utf-8"))


def format_size(size: int) -> str:
    """Format a byte size using human-readable units."""
    if size < 1024:
        return f"{size}B"
    units = ["K", "M", "G", "T"]
    value = float(size)
    unit_index = -1
    while value >= 1024 and unit_index < len(units) - 1:
        value /= 1024
        unit_index += 1
    return f"{value:.1f}{units[unit_index]}"
