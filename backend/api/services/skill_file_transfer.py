"""R2-aware file transfer helpers for skills."""
from __future__ import annotations

import mimetypes
import tempfile
from pathlib import Path
from typing import Tuple

from api.config import settings
from api.models.file_ingestion import IngestedFile, FileDerivative
from api.services.skill_file_ops import (
    download_file,
    upload_file,
    normalize_path,
    ensure_allowed_path,
    session_for_user,
)
from api.services.storage.service import get_storage_backend


def storage_is_r2() -> bool:
    """Return True if the configured storage backend is R2."""
    return settings.storage_backend.lower() == "r2"


def temp_root(prefix: str) -> Path:
    """Create a temporary root directory."""
    return Path(tempfile.mkdtemp(prefix=prefix))


def prepare_input_path(user_id: str, path: str, root: Path) -> Path:
    """Resolve an input path to a local file.

    Args:
        user_id: Current user ID.
        path: R2 or local path.
        root: Local temp root.

    Returns:
        Local filesystem path to the input.
    """
    if not storage_is_r2():
        return Path(path)
    if not user_id:
        raise ValueError("user_id is required for storage access")

    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)
    local_path = root / normalized
    download_file(user_id, normalized, local_path)
    return local_path


def prepare_output_path(user_id: str, path: str, root: Path) -> Tuple[Path, str]:
    """Return local output path and R2 target path.

    Args:
        user_id: Current user ID.
        path: Desired output path.
        root: Local temp root.

    Returns:
        Tuple of (local_path, r2_path).
    """
    if not storage_is_r2():
        return Path(path), path
    if not user_id:
        raise ValueError("user_id is required for storage access")

    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)
    local_path = root / normalized
    local_path.parent.mkdir(parents=True, exist_ok=True)
    return local_path, normalized


def upload_output_path(user_id: str, r2_path: str, local_path: Path) -> str:
    """Upload a local file to R2 and return its stored path."""
    content_type = mimetypes.guess_type(local_path.name)[0] or "application/octet-stream"
    record = upload_file(user_id, r2_path, local_path, content_type=content_type)
    if record.path is None:
        raise ValueError("Uploaded file missing path")
    return record.path


def upload_output_dir(user_id: str, r2_prefix: str, local_dir: Path) -> list[str]:
    """Upload all files in a local directory to R2.

    Args:
        user_id: Current user ID.
        r2_prefix: R2 prefix to upload under.
        local_dir: Local directory to upload from.

    Returns:
        List of uploaded R2 paths.
    """
    uploaded: list[str] = []
    base_prefix = r2_prefix.strip("/")
    for file_path in local_dir.rglob("*"):
        if not file_path.is_file():
            continue
        rel = file_path.relative_to(local_dir).as_posix()
        r2_path = f"{base_prefix}/{rel}".strip("/")
        uploaded.append(upload_output_path(user_id, r2_path, file_path))
    return uploaded


def download_input_dir(user_id: str, r2_prefix: str, local_dir: Path) -> Path:
    """Download an R2 directory to a local directory.

    Args:
        user_id: Current user ID.
        r2_prefix: R2 prefix to download.
        local_dir: Local directory destination.

    Returns:
        Local directory path containing downloaded files.
    """
    if not storage_is_r2():
        return Path(r2_prefix)
    if not user_id:
        raise ValueError("user_id is required for storage access")

    prefix = normalize_path(r2_prefix, allow_root=False)
    ensure_allowed_path(prefix)

    storage = get_storage_backend()
    with session_for_user(user_id) as db:
        records = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.like(f"{prefix}/%"),
            )
            .all()
        )
        file_ids = [record.id for record in records]
        derivatives_by_file = {}
        if file_ids:
            derivatives_by_file = {
                item.file_id: item
                for item in db.query(FileDerivative)
                .filter(
                    FileDerivative.file_id.in_(file_ids),
                    FileDerivative.kind.in_(
                        [
                            "viewer_pdf",
                            "image_original",
                            "audio_original",
                            "text_original",
                            "viewer_json",
                            "ai_md",
                        ]
                    ),
                )
                .all()
            }

    for record in records:
        if not record.path:
            continue
        if record.path.startswith("profile-images/") or record.path == "profile-images":
            continue
        derivative = derivatives_by_file.get(record.id)
        if not derivative:
            continue
        rel = record.path[len(prefix) + 1 :]
        local_path = local_dir / rel
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(storage.get_object(derivative.storage_key))

    return local_dir
