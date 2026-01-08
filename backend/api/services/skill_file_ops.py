"""Shared file operations for skills backed by storage + metadata."""

from __future__ import annotations

from api.services.file_search_service import FileSearchService
from api.services.skill_file_ops_ingestion import (
    copy_path,
    delete_path,
    download_file,
    info,
    list_entries,
    move_path,
    read_text,
    upload_file,
    write_text,
)
from api.services.skill_file_ops_paths import (
    PROFILE_IMAGES_PREFIX,
    bucket_key,
    ensure_allowed_path,
    is_profile_images_path,
    normalize_path,
    relative_path,
    session_for_user,
)

__all__ = [
    "PROFILE_IMAGES_PREFIX",
    "bucket_key",
    "ensure_allowed_path",
    "is_profile_images_path",
    "normalize_path",
    "relative_path",
    "session_for_user",
    "delete_path",
    "download_file",
    "info",
    "list_entries",
    "copy_path",
    "move_path",
    "read_text",
    "search_entries",
    "upload_file",
    "write_text",
]

search_entries = FileSearchService.search_entries
