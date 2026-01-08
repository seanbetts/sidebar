"""Helpers for ingestion-backed fs operations."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from hashlib import sha256
from pathlib import Path
from typing import Any

from api.models.file_ingestion import FileDerivative, FileProcessingJob, IngestedFile

STAGING_ROOT = Path("/tmp/sidebar-ingestion")


def now_utc() -> datetime:
    """Return the current UTC timestamp."""
    return datetime.now(UTC)


def staging_path(file_id: str) -> Path:
    """Return the staging path for a file id."""
    return STAGING_ROOT / file_id / "source"


def strip_frontmatter(content: str) -> str:
    """Remove YAML frontmatter from markdown content."""
    if not content.startswith("---\n"):
        return content
    marker = "\n---\n"
    idx = content.find(marker)
    if idx == -1:
        return content
    return content[idx + len(marker) :]


def build_frontmatter(record: IngestedFile, derivative_kind: str) -> str:
    """Build standardized YAML frontmatter for an ingestion record."""
    return (
        "---\n"
        f"file_id: {record.id}\n"
        f"source_filename: {record.filename_original}\n"
        f"source_mime: {record.mime_original}\n"
        f"created_at: {record.created_at.isoformat()}\n"
        f"sha256: {record.sha256}\n"
        "derivatives:\n"
        f"  {derivative_kind}: true\n"
        "---\n\n"
    )


def find_record_by_path(db, user_id: str, path: str) -> IngestedFile | None:
    """Return the newest ingested file record for a path."""
    return (
        db.query(IngestedFile)
        .filter(
            IngestedFile.user_id == user_id,
            IngestedFile.path == path,
            IngestedFile.deleted_at.is_(None),
        )
        .order_by(IngestedFile.created_at.desc())
        .first()
    )


def get_job(db, file_id) -> FileProcessingJob | None:
    """Return the processing job for a file id."""
    return (
        db.query(FileProcessingJob).filter(FileProcessingJob.file_id == file_id).first()
    )


def get_derivative(db, file_id, kind: str) -> FileDerivative | None:
    """Return a specific derivative record for a file id."""
    return (
        db.query(FileDerivative)
        .filter(
            FileDerivative.file_id == file_id,
            FileDerivative.kind == kind,
        )
        .first()
    )


def pick_derivative(db, file_id) -> FileDerivative | None:
    """Pick the best available derivative for a file id."""
    preferred = [
        "viewer_pdf",
        "image_original",
        "audio_original",
        "text_original",
        "viewer_json",
        "ai_md",
    ]
    derivatives = (
        db.query(FileDerivative).filter(FileDerivative.file_id == file_id).all()
    )
    by_kind = {item.kind: item for item in derivatives}
    for kind in preferred:
        if kind in by_kind:
            return by_kind[kind]
    return derivatives[0] if derivatives else None


def hash_bytes(data: bytes) -> str:
    """Return a SHA-256 hex digest for the given bytes."""
    return sha256(data).hexdigest()


def yaml_escape(value: str) -> str:
    """Escape YAML string values for ai.md frontmatter."""
    if value == "":
        return '""'
    if (
        any(ch in value for ch in (":", "#", "[", "]", "{", "}", ",", "&", "*", "?"))
        or value.startswith(("-", "?", "@"))
        or " " in value
    ):
        return json.dumps(value)
    return value


def yaml_value(value: Any) -> str:
    """Normalize primitive values for YAML output."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int | float):
        return str(value)
    return yaml_escape(str(value))


def sanitize_kind(kind: str) -> str:
    """Normalize derivative kind strings for storage keys."""
    return kind.replace("/", "_").replace("\\", "_")
