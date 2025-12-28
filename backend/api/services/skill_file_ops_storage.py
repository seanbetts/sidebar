"""Storage operations for skill-backed files."""
from __future__ import annotations

import fnmatch
import mimetypes
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from api.models.file_object import FileObject
from api.services.files_service import FilesService
from api.services.skill_file_ops_paths import (
    bucket_key,
    ensure_allowed_path,
    is_profile_images_path,
    normalize_path,
    relative_path,
    session_for_user,
)
from api.services.storage.service import get_storage_backend


def list_entries(
    user_id: str,
    directory: str,
    pattern: str = "*",
    recursive: bool = False,
) -> dict:
    base_path = normalize_path(directory)
    if base_path:
        ensure_allowed_path(base_path)

    with session_for_user(user_id) as db:
        records = FilesService.list_by_prefix(db, user_id, base_path)

    records = [
        record
        for record in records
        if record.deleted_at is None and not is_profile_images_path(record.path)
    ]

    if base_path and not records:
        raise FileNotFoundError(f"Directory not found: {directory}")

    entries: list[dict] = []
    dir_meta: dict[str, datetime] = {}

    def register_dir(path: str, updated_at: Optional[datetime]) -> None:
        if not path:
            return
        existing = dir_meta.get(path)
        if updated_at and (existing is None or updated_at > existing):
            dir_meta[path] = updated_at
        elif existing is None:
            dir_meta[path] = updated_at or datetime.now(timezone.utc)

    for record in records:
        rel_path = relative_path(base_path, record.path)
        if rel_path == "" and record.category != "folder":
            continue

        parts = [part for part in rel_path.split("/") if part]
        if record.category == "folder":
            if not parts:
                continue
            dir_path = "/".join(parts)
            register_dir(dir_path, record.updated_at)
            for idx in range(1, len(parts)):
                register_dir("/".join(parts[:idx]), record.updated_at)
            continue

        if not parts:
            continue

        for idx in range(1, len(parts)):
            register_dir("/".join(parts[:idx]), record.updated_at)

        if not recursive and len(parts) > 1:
            continue

        if not fnmatch.fnmatch(parts[-1], pattern):
            continue

        entries.append(
            {
                "name": parts[-1],
                "path": "/".join(parts),
                "size": record.size,
                "modified": record.updated_at.isoformat() if record.updated_at else None,
                "is_file": True,
                "is_directory": False,
            }
        )

    for dir_path, updated_at in dir_meta.items():
        if not recursive and "/" in dir_path:
            continue
        if not fnmatch.fnmatch(Path(dir_path).name, pattern):
            continue
        entries.append(
            {
                "name": Path(dir_path).name,
                "path": dir_path,
                "size": 0,
                "modified": updated_at.isoformat() if updated_at else None,
                "is_file": False,
                "is_directory": True,
            }
        )

    entries.sort(key=lambda item: item["path"])

    return {
        "directory": base_path or ".",
        "files": entries,
        "count": len(entries),
    }


def read_text(
    user_id: str,
    path: str,
) -> tuple[str, FileObject]:
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        record = FilesService.get_by_path(db, user_id, normalized)
        if not record or record.deleted_at is not None:
            raise FileNotFoundError(f"File not found: {path}")
        if record.category == "folder":
            raise ValueError(f"Path is a directory: {path}")

    storage = get_storage_backend()
    raw = storage.get_object(record.bucket_key)
    return raw.decode("utf-8", errors="ignore"), record


def write_text(
    user_id: str,
    path: str,
    content: str,
    *,
    mode: str = "replace",
) -> dict:
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        existing = FilesService.get_by_path(db, user_id, normalized)

    if mode == "create" and existing:
        raise FileExistsError(f"File already exists: {path}")
    if mode == "append" and not existing:
        existing = None

    data = content
    if mode == "append" and existing:
        storage = get_storage_backend()
        raw = storage.get_object(existing.bucket_key)
        data = raw.decode("utf-8", errors="ignore") + content

    storage = get_storage_backend()
    content_type = mimetypes.guess_type(normalized)[0] or "text/plain"
    bucket = bucket_key(user_id, normalized)
    obj = storage.put_object(bucket, data.encode("utf-8"), content_type=content_type)

    with session_for_user(user_id) as db:
        FilesService.upsert_file(
            db,
            user_id,
            normalized,
            bucket_key=bucket,
            size=obj.size,
            content_type=content_type,
            etag=obj.etag,
            category=None,
        )

    action = "created" if not existing else ("appended" if mode == "append" else "updated")
    return {
        "path": normalized,
        "action": action,
        "size": obj.size,
        "lines": len(data.splitlines()),
    }


def upload_file(
    user_id: str,
    path: str,
    local_path: Path,
    *,
    content_type: Optional[str] = None,
    category: Optional[str] = None,
) -> FileObject:
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    data = local_path.read_bytes()
    resolved_content_type = content_type or mimetypes.guess_type(normalized)[0] or "application/octet-stream"
    storage = get_storage_backend()
    key = bucket_key(user_id, normalized, is_folder=category == "folder")
    obj = storage.put_object(key, data, content_type=resolved_content_type)

    with session_for_user(user_id) as db:
        FilesService.upsert_file(
            db,
            user_id,
            normalized,
            bucket_key=key,
            size=obj.size,
            content_type=resolved_content_type,
            etag=obj.etag,
            category=category,
        )
        record = FilesService.get_by_path(db, user_id, normalized)

    return record


def download_file(user_id: str, path: str, local_path: Path) -> FileObject:
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        record = FilesService.get_by_path(db, user_id, normalized)
        if not record or record.deleted_at is not None:
            raise FileNotFoundError(f"File not found: {path}")
        if record.category == "folder":
            raise ValueError(f"Path is a directory: {path}")

    storage = get_storage_backend()
    local_path.parent.mkdir(parents=True, exist_ok=True)
    local_path.write_bytes(storage.get_object(record.bucket_key))
    return record


def create_folder(user_id: str, path: str) -> dict:
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        existing = FilesService.get_by_path(db, user_id, normalized)
        if existing and existing.category == "folder":
            return {"path": normalized, "action": "exists"}
        bucket = bucket_key(user_id, normalized, is_folder=True)
        FilesService.upsert_file(
            db,
            user_id,
            normalized,
            bucket_key=bucket,
            size=0,
            content_type=None,
            etag=None,
            category="folder",
        )

    return {"path": normalized, "action": "created"}


def delete_path(user_id: str, path: str) -> dict:
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)
    storage = get_storage_backend()

    with session_for_user(user_id) as db:
        record = FilesService.get_by_path(db, user_id, normalized)
        if record and record.category != "folder":
            storage.delete_object(record.bucket_key)
            FilesService.mark_deleted(db, user_id, normalized)
            return {"deleted": [normalized], "count": 1}

        prefix = f"{normalized}/"
        records = FilesService.list_by_prefix(db, user_id, prefix)
        records = [
            item for item in records
            if item.deleted_at is None and not is_profile_images_path(item.path)
        ]
        if not records and not record:
            raise FileNotFoundError(f"Path not found: {path}")

        deleted = []
        for item in records:
            storage.delete_object(item.bucket_key)
            FilesService.mark_deleted(db, user_id, item.path)
            deleted.append(item.path)

        if record and record.category == "folder":
            FilesService.mark_deleted(db, user_id, normalized)
            deleted.append(normalized)

    return {"deleted": deleted, "count": len(deleted)}


def move_path(user_id: str, source: str, destination: str) -> dict:
    src = normalize_path(source, allow_root=False)
    dest = normalize_path(destination, allow_root=False)
    ensure_allowed_path(src)
    ensure_allowed_path(dest)

    with session_for_user(user_id) as db:
        dest_record = FilesService.get_any_by_path(db, user_id, dest)
        if dest_record:
            if dest_record.deleted_at is None:
                raise FileExistsError(f"Destination already exists: {destination}")
            FilesService.delete_any_by_path(db, user_id, dest)

        record = FilesService.get_by_path(db, user_id, src)
        storage = get_storage_backend()

        if record and record.category != "folder":
            old_key = record.bucket_key
            new_key = bucket_key(user_id, dest)
            storage.move_object(old_key, new_key)
            record.path = dest
            record.bucket_key = new_key
            record.updated_at = datetime.now(timezone.utc)
            db.commit()
            return {"source": src, "destination": dest, "type": "file"}

        prefix = f"{src}/"
        records = FilesService.list_by_prefix(db, user_id, prefix)
        records = [
            item for item in records
            if item.deleted_at is None and not is_profile_images_path(item.path)
        ]
        if not records and not (record and record.category == "folder"):
            raise FileNotFoundError(f"Source not found: {source}")

        for item in records:
            suffix = item.path[len(prefix):]
            new_path = f"{dest}/{suffix}" if suffix else dest
            new_key = bucket_key(user_id, new_path, is_folder=item.category == "folder")
            storage.move_object(item.bucket_key, new_key)
            item.path = new_path
            item.bucket_key = new_key
            item.updated_at = datetime.now(timezone.utc)

        if record and record.category == "folder":
            record.path = dest
            record.bucket_key = bucket_key(user_id, dest, is_folder=True)
            record.updated_at = datetime.now(timezone.utc)

        db.commit()

    return {"source": src, "destination": dest, "type": "directory"}


def copy_path(user_id: str, source: str, destination: str) -> dict:
    src = normalize_path(source, allow_root=False)
    dest = normalize_path(destination, allow_root=False)
    ensure_allowed_path(src)
    ensure_allowed_path(dest)

    storage = get_storage_backend()

    with session_for_user(user_id) as db:
        dest_record = FilesService.get_any_by_path(db, user_id, dest)
        if dest_record:
            if dest_record.deleted_at is None:
                raise FileExistsError(f"Destination already exists: {destination}")
            FilesService.delete_any_by_path(db, user_id, dest)

        record = FilesService.get_by_path(db, user_id, src)
        if record and record.category != "folder":
            new_key = bucket_key(user_id, dest)
            storage.copy_object(record.bucket_key, new_key)
            FilesService.upsert_file(
                db,
                user_id,
                dest,
                bucket_key=new_key,
                size=record.size,
                content_type=record.content_type,
                etag=record.etag,
                category=record.category,
            )
            return {"source": src, "destination": dest, "type": "file"}

        prefix = f"{src}/"
        records = FilesService.list_by_prefix(db, user_id, prefix)
        records = [
            item for item in records
            if item.deleted_at is None and not is_profile_images_path(item.path)
        ]
        if not records and not (record and record.category == "folder"):
            raise FileNotFoundError(f"Source not found: {source}")

        for item in records:
            suffix = item.path[len(prefix):]
            new_path = f"{dest}/{suffix}" if suffix else dest
            new_key = bucket_key(user_id, new_path, is_folder=item.category == "folder")
            storage.copy_object(item.bucket_key, new_key)
            FilesService.upsert_file(
                db,
                user_id,
                new_path,
                bucket_key=new_key,
                size=item.size,
                content_type=item.content_type,
                etag=item.etag,
                category=item.category,
            )

        if record and record.category == "folder":
            FilesService.upsert_file(
                db,
                user_id,
                dest,
                bucket_key=bucket_key(user_id, dest, is_folder=True),
                size=0,
                content_type=None,
                etag=None,
                category="folder",
            )

    return {"source": src, "destination": dest, "type": "directory"}


def info(user_id: str, path: str) -> dict:
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        record = FilesService.get_by_path(db, user_id, normalized)
        if record and record.deleted_at is None:
            return {
                "path": record.path,
                "size": record.size,
                "modified": record.updated_at.isoformat() if record.updated_at else None,
                "is_file": record.category != "folder",
                "is_directory": record.category == "folder",
            }

        prefix = f"{normalized}/"
        records = FilesService.list_by_prefix(db, user_id, prefix)
        records = [
            item for item in records
            if item.deleted_at is None and not is_profile_images_path(item.path)
        ]
        if not records:
            raise FileNotFoundError(f"Path not found: {path}")

    return {
        "path": normalized,
        "size": 0,
        "modified": None,
        "is_file": False,
        "is_directory": True,
    }
