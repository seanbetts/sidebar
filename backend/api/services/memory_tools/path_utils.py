"""Path utilities for memory tool handling."""
from __future__ import annotations

import urllib.parse
from typing import Any

from api.services.memory_tools.constants import HIDDEN_PATTERN, MAX_PATH_LENGTH


def normalize_path(path: Any) -> str:
    """Normalize and validate a memory path.

    Args:
        path: Raw path input.

    Returns:
        Normalized memory path starting with /memories.

    Raises:
        ValueError: If the path is invalid or unsafe.
    """
    if not isinstance(path, str):
        raise ValueError("Invalid path")
    path = path.strip()
    if len(path) > MAX_PATH_LENGTH:
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


def is_visible_path(path: str) -> bool:
    """Return True if the path should be visible in listings."""
    if not path.startswith("/memories"):
        return False
    parts = path[len("/memories"):].split("/")
    for part in parts:
        if part in {"", "."}:
            continue
        if part == "node_modules":
            return False
        if HIDDEN_PATTERN.match(part):
            return False
    return True
