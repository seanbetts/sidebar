#!/usr/bin/env python3
"""
Sync /workspace contents to R2 and backfill file metadata.
"""
from __future__ import annotations

import argparse
import mimetypes
from pathlib import Path

from sqlalchemy import text

from api.db.session import SessionLocal, set_session_user_id
from api.db.dependencies import DEFAULT_USER_ID
from api.services.files_service import FilesService
from api.services.user_settings_service import UserSettingsService
from api.services.storage.service import get_storage_backend


EXCLUDES = {".git", "__pycache__", "node_modules"}


def should_skip(path: Path) -> bool:
    if path.name.startswith("."):
        return True
    if path.name in EXCLUDES:
        return True
    return False


def category_from_path(relative_path: str) -> str:
    parts = [part for part in relative_path.split("/") if part]
    return parts[0] if parts else "documents"


def sync_workspace(workspace: Path, user_id: str, dry_run: bool = False) -> None:
    storage = get_storage_backend()
    db = SessionLocal()
    set_session_user_id(db, user_id)
    db.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})

    try:
        for path in sorted(workspace.rglob("*")):
            if should_skip(path):
                continue
            rel_path = path.relative_to(workspace).as_posix()
            if path.is_dir():
                bucket_key = f"{user_id}/{rel_path}/"
                if dry_run:
                    continue
                FilesService.upsert_file(
                    db,
                    user_id,
                    rel_path,
                    bucket_key=bucket_key,
                    size=0,
                    content_type=None,
                    etag=None,
                    category="folder",
                )
                continue

            data = path.read_bytes()
            content_type, _ = mimetypes.guess_type(path.name)
            bucket_key = f"{user_id}/{rel_path}"
            if not dry_run:
                storage.put_object(bucket_key, data, content_type=content_type)
                FilesService.upsert_file(
                    db,
                    user_id,
                    rel_path,
                    bucket_key=bucket_key,
                    size=len(data),
                    content_type=content_type,
                    etag=None,
                    category=category_from_path(rel_path),
                )
                if rel_path.startswith("profile-images/") and rel_path.endswith(
                    f"{user_id}.{path.suffix.lstrip('.')}"
                ):
                    UserSettingsService.upsert_settings(
                        db,
                        user_id,
                        profile_image_path=bucket_key,
                    )
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync /workspace to R2 and backfill files table.")
    parser.add_argument("--workspace", default="/workspace", help="Workspace root path")
    parser.add_argument("--user-id", default=DEFAULT_USER_ID, help="User id for metadata")
    parser.add_argument("--dry-run", action="store_true", help="Skip uploads and DB writes")
    args = parser.parse_args()

    sync_workspace(Path(args.workspace), args.user_id, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
