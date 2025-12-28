"""Path helpers for skill-backed file operations."""
from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path

from api.db.session import SessionLocal, set_session_user_id


PROFILE_IMAGES_PREFIX = "profile-images"


def normalize_path(raw_path: str, *, allow_root: bool = True) -> str:
    """Normalize a user-provided path to a relative POSIX path.

    Args:
        raw_path: Raw user-provided path.
        allow_root: Allow empty paths to represent the root. Defaults to True.

    Returns:
        Normalized path without leading slash.

    Raises:
        ValueError: If the path is invalid or contains traversal.
    """
    if raw_path is None:
        raise ValueError("Path is required")

    path = str(raw_path).strip()
    if path in {"", ".", "/"}:
        if allow_root:
            return ""
        raise ValueError("Path cannot be empty")

    path = path.replace("\\", "/")
    if path.startswith("/"):
        path = path[1:]

    parts = [part for part in Path(path).parts if part not in {"", "."}]
    if any(part == ".." for part in parts):
        raise ValueError(f"Path traversal not allowed: {raw_path}")

    normalized = "/".join(parts)
    if not normalized and not allow_root:
        raise ValueError("Path cannot be empty")
    return normalized


def is_profile_images_path(path: str) -> bool:
    """Return True if the path is within profile-images."""
    normalized = normalize_path(path)
    return normalized == PROFILE_IMAGES_PREFIX or normalized.startswith(f"{PROFILE_IMAGES_PREFIX}/")


def ensure_allowed_path(path: str) -> None:
    """Block access to profile-images from skill file operations."""
    if is_profile_images_path(path):
        raise ValueError("Access to profile-images is not allowed")


def bucket_key(user_id: str, path: str, *, is_folder: bool = False) -> str:
    """Build a bucket key for a user and path.

    Args:
        user_id: Current user ID.
        path: Relative path.
        is_folder: Whether the key represents a folder marker.

    Returns:
        Bucket key string.
    """
    key = f"{user_id}/{path.strip('/')}"
    if is_folder:
        return f"{key}/" if key and not key.endswith("/") else key
    return key


def relative_path(base_path: str, full_path: str) -> str:
    """Return a path relative to a base path.

    Args:
        base_path: Base folder path.
        full_path: Full path including base.

    Returns:
        Relative path string.
    """
    base = (base_path or "").strip("/")
    path = (full_path or "").strip("/")
    if not base:
        return path
    if path == base:
        return ""
    if path.startswith(f"{base}/"):
        return path[len(base) + 1 :]
    return ""


@contextmanager
def session_for_user(user_id: str):
    """Provide a DB session scoped to a user ID."""
    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        yield db
    finally:
        db.close()
