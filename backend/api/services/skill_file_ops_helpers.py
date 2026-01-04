"""Helpers for ingestion-backed fs operations."""
from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from typing import Optional

from api.models.file_ingestion import IngestedFile, FileDerivative, FileProcessingJob

STAGING_ROOT = Path("/tmp/sidebar-ingestion")


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def staging_path(file_id: str) -> Path:
    return STAGING_ROOT / file_id / "source"


def strip_frontmatter(content: str) -> str:
    if not content.startswith("---\n"):
        return content
    marker = "\n---\n"
    idx = content.find(marker)
    if idx == -1:
        return content
    return content[idx + len(marker):]


def build_frontmatter(record: IngestedFile, derivative_kind: str) -> str:
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


def find_record_by_path(db, user_id: str, path: str) -> Optional[IngestedFile]:
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


def get_job(db, file_id) -> Optional[FileProcessingJob]:
    return (
        db.query(FileProcessingJob)
        .filter(FileProcessingJob.file_id == file_id)
        .first()
    )


def get_derivative(db, file_id, kind: str) -> Optional[FileDerivative]:
    return (
        db.query(FileDerivative)
        .filter(
            FileDerivative.file_id == file_id,
            FileDerivative.kind == kind,
        )
        .first()
    )


def pick_derivative(db, file_id) -> Optional[FileDerivative]:
    preferred = [
        "viewer_pdf",
        "image_original",
        "audio_original",
        "text_original",
        "viewer_json",
        "ai_md",
    ]
    derivatives = (
        db.query(FileDerivative)
        .filter(FileDerivative.file_id == file_id)
        .all()
    )
    by_kind = {item.kind: item for item in derivatives}
    for kind in preferred:
        if kind in by_kind:
            return by_kind[kind]
    return derivatives[0] if derivatives else None


def hash_bytes(data: bytes) -> str:
    return sha256(data).hexdigest()
