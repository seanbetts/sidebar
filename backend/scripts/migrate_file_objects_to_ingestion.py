#!/usr/bin/env python3
"""Migrate file_objects records into ingested_files."""
from __future__ import annotations

import argparse
import os
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from uuid import uuid4

from sqlalchemy import or_


def _load_env() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    for filename in (".env.local", ".env"):
        env_path = repo_root / filename
        if not env_path.exists():
            continue
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip("\"'")
            os.environ.setdefault(key, value)
        break


_load_env()

from api.db.session import SessionLocal, set_session_user_id
from api.models.file_object import FileObject
from api.models.file_ingestion import IngestedFile
from api.services.file_ingestion_service import FileIngestionService
from api.services.skill_file_ops_paths import is_profile_images_path
from api.services.storage.service import get_storage_backend


STAGING_ROOT = Path("/tmp/sidebar-ingestion")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _staging_path(file_id: str) -> Path:
    return STAGING_ROOT / file_id / "source"


def _iter_user_ids(db, user_id: str | None) -> list[str]:
    if user_id:
        return [user_id]
    return [row[0] for row in db.query(FileObject.user_id).distinct().all()]


def migrate_file_objects(
    *,
    user_id: str | None = None,
    limit: int | None = None,
    dry_run: bool = False,
) -> dict:
    storage = get_storage_backend()
    print(f"Storage backend: {storage.__class__.__name__}")
    migrated = 0
    skipped = 0
    failed = 0

    with SessionLocal() as db:
        user_ids = _iter_user_ids(db, user_id)
        for uid in user_ids:
            set_session_user_id(db, uid)
            query = (
                db.query(FileObject)
                .filter(
                    FileObject.user_id == uid,
                    FileObject.deleted_at.is_(None),
                    or_(FileObject.category.is_(None), FileObject.category != "folder"),
                )
                .order_by(FileObject.updated_at.desc())
            )
            if limit:
                query = query.limit(limit)
            records = query.all()
            if not records:
                continue

            for record in records:
                if not record.path or is_profile_images_path(record.path):
                    skipped += 1
                    continue
                if not record.bucket_key:
                    skipped += 1
                    continue

                existing = (
                    db.query(IngestedFile)
                    .filter(
                        IngestedFile.user_id == uid,
                        IngestedFile.path == record.path,
                        IngestedFile.deleted_at.is_(None),
                    )
                    .first()
                )
                if existing:
                    skipped += 1
                    continue

                if dry_run:
                    print(f"[dry-run] {uid} {record.path}")
                    migrated += 1
                    continue

                try:
                    content = storage.get_object(record.bucket_key)
                except Exception as exc:
                    failed += 1
                    print(f"[error] Failed to fetch {record.path}: {exc}")
                    continue

                file_id = uuid4()
                staging_path = _staging_path(str(file_id))
                staging_path.parent.mkdir(parents=True, exist_ok=True)
                staging_path.write_bytes(content)

                digest = sha256(content).hexdigest()
                size = len(content)
                filename = Path(record.path).name or "upload"
                mime = record.content_type or "application/octet-stream"
                created_at = record.updated_at or record.created_at or _now()
                source_metadata = {
                    "migrated_from": "file_objects",
                    "file_object_id": str(record.id),
                    "file_object_path": record.path,
                }

                new_record, _ = FileIngestionService.create_ingestion(
                    db,
                    uid,
                    filename_original=filename,
                    path=record.path,
                    mime_original=mime,
                    size_bytes=size,
                    sha256=digest,
                    file_id=file_id,
                    source_metadata=source_metadata,
                )
                new_record.created_at = created_at
                db.commit()
                migrated += 1

    return {"migrated": migrated, "skipped": skipped, "failed": failed}


def main() -> None:
    parser = argparse.ArgumentParser(description="Migrate file_objects to ingested_files.")
    parser.add_argument("--user-id", help="Limit migration to a single user.")
    parser.add_argument("--limit", type=int, help="Limit files per user.")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without writing.")
    args = parser.parse_args()

    summary = migrate_file_objects(
        user_id=args.user_id,
        limit=args.limit,
        dry_run=args.dry_run,
    )
    print(
        "Migration summary:"
        f" migrated={summary['migrated']}"
        f" skipped={summary['skipped']}"
        f" failed={summary['failed']}"
    )


if __name__ == "__main__":
    main()
