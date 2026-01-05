"""Ingestion-backed file operations for fs skill."""
from __future__ import annotations

import fnmatch
import mimetypes
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Optional
from uuid import uuid4

from api.models.file_ingestion import IngestedFile, FileDerivative, FileProcessingJob
from api.db.session import set_session_user_id
from api.services.skill_file_ops_helpers import (
    build_frontmatter,
    find_record_by_path,
    get_derivative,
    get_job,
    hash_bytes,
    now_utc,
    pick_derivative,
    staging_path,
    strip_frontmatter,
)
from api.services.skill_file_ops_paths import (
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
    """List entries under a directory for the fs skill."""
    base_path = normalize_path(directory)
    if base_path:
        ensure_allowed_path(base_path)

    with session_for_user(user_id) as db:
        if base_path:
            match = f"{base_path}/%"
            records = (
                db.query(IngestedFile)
                .filter(
                    IngestedFile.user_id == user_id,
                    IngestedFile.deleted_at.is_(None),
                    IngestedFile.path.is_not(None),
                    IngestedFile.path.like(match),
                )
                .order_by(IngestedFile.created_at.desc())
                .all()
            )
        else:
            records = (
                db.query(IngestedFile)
                .filter(
                    IngestedFile.user_id == user_id,
                    IngestedFile.deleted_at.is_(None),
                    IngestedFile.path.is_not(None),
                )
                .order_by(IngestedFile.created_at.desc())
                .all()
            )

    records = [
        record
        for record in records
        if record.path and not is_profile_images_path(record.path)
    ]

    if base_path and not records:
        raise FileNotFoundError(f"Directory not found: {directory}")

    latest_by_path: dict[str, IngestedFile] = {}
    for record in records:
        latest_by_path.setdefault(record.path, record)

    entries: list[dict] = []
    dir_meta: dict[str, datetime] = {}

    def register_dir(path: str, updated_at: Optional[datetime]) -> None:
        if not path:
            return
        existing = dir_meta.get(path)
        if updated_at and (existing is None or updated_at > existing):
            dir_meta[path] = updated_at
        elif existing is None:
            dir_meta[path] = updated_at or now_utc()

    for record in latest_by_path.values():
        if record.path is None:
            continue
        rel_path = relative_path(base_path, record.path)
        if rel_path == "":
            continue
        parts = [part for part in rel_path.split("/") if part]
        if not parts:
            continue
        for idx in range(1, len(parts)):
            register_dir("/".join(parts[:idx]), record.created_at)
        if not recursive and len(parts) > 1:
            continue
        if not fnmatch.fnmatch(parts[-1], pattern):
            continue
        entries.append(
            {
                "name": parts[-1],
                "path": "/".join(parts),
                "size": record.size_bytes,
                "modified": record.created_at.isoformat() if record.created_at else None,
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


def read_text(user_id: str, path: str) -> tuple[str, IngestedFile]:
    """Read ai.md content for a file."""
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        record = find_record_by_path(db, user_id, normalized)
        if not record:
            prefix = f"{normalized}/"
            has_children = (
                db.query(IngestedFile)
                .filter(
                    IngestedFile.user_id == user_id,
                    IngestedFile.deleted_at.is_(None),
                    IngestedFile.path.like(f"{prefix}%"),
                )
                .first()
            )
            if has_children:
                raise ValueError(f"Path is a directory: {path}")
            raise FileNotFoundError(f"File not found: {path}")

        derivative = get_derivative(db, record.id, "ai_md")
        if not derivative:
            job = get_job(db, record.id)
            if job and job.status != "ready":
                raise ValueError(f"File not ready yet (status: {job.status})")
            derivative = get_derivative(db, record.id, "text_original")
        if not derivative:
            raise ValueError(f"No readable content for: {path}")

    storage = get_storage_backend()
    raw = storage.get_object(derivative.storage_key)
    content = raw.decode("utf-8", errors="ignore")
    if derivative.kind != "ai_md":
        content = f"{build_frontmatter(record, derivative.kind)}{content}"
    return content, record


def write_text(
    user_id: str,
    path: str,
    content: str,
    *,
    mode: str = "replace",
    wait_for_ready: bool = False,
    timeout_seconds: float = 25.0,
) -> dict:
    """Write text content by creating an ingestion job."""
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        existing = find_record_by_path(db, user_id, normalized)

        if mode == "create" and existing:
            raise FileExistsError(f"File already exists: {path}")

        if mode == "append" and existing:
            derivative = get_derivative(db, existing.id, "text_original")
            if derivative is None:
                derivative = get_derivative(db, existing.id, "ai_md")
            if derivative is None:
                raise ValueError(f"File not ready for append: {path}")
            storage = get_storage_backend()
            raw = storage.get_object(derivative.storage_key).decode("utf-8", errors="ignore")
            base_content = strip_frontmatter(raw)
            content = base_content + content

        file_id = existing.id if existing else uuid4()
        content_bytes = content.encode("utf-8")
        digest = hash_bytes(content_bytes)
        size = len(content_bytes)
        filename = Path(normalized).name or "untitled.txt"
        mime = mimetypes.guess_type(normalized)[0] or "text/plain"

        source_path = staging_path(str(file_id))
        source_path.parent.mkdir(parents=True, exist_ok=True)
        source_path.write_bytes(content_bytes)

        now = now_utc()
        if existing:
            existing.filename_original = filename
            existing.path = normalized
            existing.mime_original = mime
            existing.size_bytes = size
            existing.sha256 = digest
            existing.deleted_at = None
            existing.created_at = now
            record = existing
        else:
            record = IngestedFile(
                id=file_id,
                user_id=user_id,
                filename_original=filename,
                path=normalized,
                mime_original=mime,
                size_bytes=size,
                sha256=digest,
                created_at=now,
                deleted_at=None,
            )
            db.add(record)
        db.flush()
        set_session_user_id(db, user_id)

        job = get_job(db, record.id)
        if job:
            job.status = "queued"
            job.stage = "queued"
            job.error_code = None
            job.error_message = None
            job.attempts = 0
            job.started_at = None
            job.finished_at = None
            job.updated_at = now
        else:
            db.add(
                FileProcessingJob(
                    file_id=record.id,
                    status="queued",
                    stage="queued",
                    attempts=0,
                    updated_at=now,
                )
            )

        db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
        db.commit()

    if os.getenv("TESTING", "").lower() in {"1", "true", "yes", "on"}:
        storage = get_storage_backend()
        storage_key = f"{user_id}/files/{record.id}/derivatives/source.txt"
        ai_key = f"{user_id}/files/{record.id}/ai/ai.md"
        storage.put_object(storage_key, content_bytes)
        storage.put_object(ai_key, content_bytes)
        with session_for_user(user_id) as db:
            db.add(
                FileDerivative(
                    file_id=record.id,
                    kind="text_original",
                    storage_key=storage_key,
                    mime="text/plain",
                    size_bytes=size,
                    sha256=digest,
                    created_at=now_utc(),
                )
            )
            db.add(
                FileDerivative(
                    file_id=record.id,
                    kind="ai_md",
                    storage_key=ai_key,
                    mime="text/markdown",
                    size_bytes=size,
                    sha256=digest,
                    created_at=now_utc(),
                )
            )
            job = get_job(db, record.id)
            if job:
                job.status = "ready"
                job.stage = "ready"
                job.error_code = None
                job.error_message = None
                job.finished_at = now_utc()
                job.updated_at = now_utc()
            db.commit()

    if wait_for_ready:
        deadline = time.monotonic() + timeout_seconds
        last_status = None
        while time.monotonic() < deadline:
            with session_for_user(user_id) as db:
                job = get_job(db, record.id)
                if not job:
                    raise ValueError(f"Processing job missing for: {path}")
                last_status = job.status
                if job.status == "ready":
                    break
                if job.status in {"failed", "canceled"}:
                    detail = job.error_message or job.error_code or job.status
                    raise ValueError(f"File processing {job.status}: {detail}")
            time.sleep(0.5)
        else:
            raise TimeoutError(f"File processing still {last_status} after {timeout_seconds:.0f}s")

    action = "created" if not existing else ("appended" if mode == "append" else "updated")
    return {
        "path": normalized,
        "action": action,
        "size": size,
        "lines": len(content.splitlines()),
        "status": "ready" if wait_for_ready else (job.status if job else "queued"),
        "file_id": str(record.id),
    }


def upload_file(
    user_id: str,
    path: str,
    local_path: Path,
    *,
    content_type: Optional[str] = None,
) -> IngestedFile:
    """Upload a local file via ingestion."""
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    content = local_path.read_bytes()
    digest = hash_bytes(content)
    size = len(content)
    filename = Path(normalized).name or "upload"
    mime = content_type or mimetypes.guess_type(filename)[0] or "application/octet-stream"

    file_id = uuid4()
    source_path = staging_path(str(file_id))
    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_bytes(content)

    now = now_utc()
    with session_for_user(user_id) as db:
        record = IngestedFile(
            id=file_id,
            user_id=user_id,
            filename_original=filename,
            path=normalized,
            mime_original=mime,
            size_bytes=size,
            sha256=digest,
            created_at=now,
            deleted_at=None,
        )
        db.add(record)
        db.flush()
        set_session_user_id(db, user_id)
        db.add(
            FileProcessingJob(
                file_id=record.id,
                status="queued",
                stage="queued",
                attempts=0,
                updated_at=now,
            )
        )
        db.commit()
        return record


def download_file(user_id: str, path: str, local_path: Path) -> IngestedFile:
    """Download a file derivative to a local path."""
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        record = find_record_by_path(db, user_id, normalized)
        if not record:
            raise FileNotFoundError(f"File not found: {path}")
        derivative = pick_derivative(db, record.id)
        if not derivative:
            raise ValueError(f"No downloadable content for: {path}")

    storage = get_storage_backend()
    local_path.parent.mkdir(parents=True, exist_ok=True)
    local_path.write_bytes(storage.get_object(derivative.storage_key))
    return record


def delete_path(user_id: str, path: str) -> dict:
    """Soft delete a file or directory path."""
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    storage = get_storage_backend()
    deleted: list[str] = []

    with session_for_user(user_id) as db:
        record = find_record_by_path(db, user_id, normalized)
        if record:
            derivatives = (
                db.query(FileDerivative)
                .filter(FileDerivative.file_id == record.id)
                .all()
            )
            for item in derivatives:
                storage.delete_object(item.storage_key)
            db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
            record.deleted_at = now_utc()
            db.commit()
            if record.path is None:
                raise ValueError(f"Missing path for record {record.id}")
            deleted.append(record.path)
            return {"deleted": deleted, "count": len(deleted)}

        prefix = f"{normalized}/"
        records = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.like(f"{prefix}%"),
            )
            .all()
        )
        if not records:
            raise FileNotFoundError(f"Path not found: {path}")

        for item in records:
            if item.path is None:
                continue
            derivatives = (
                db.query(FileDerivative)
                .filter(FileDerivative.file_id == item.id)
                .all()
            )
            for derivative in derivatives:
                storage.delete_object(derivative.storage_key)
            db.query(FileDerivative).filter(FileDerivative.file_id == item.id).delete()
            item.deleted_at = now_utc()
            deleted.append(item.path)

        db.commit()

    return {"deleted": deleted, "count": len(deleted)}


def move_path(user_id: str, source: str, destination: str) -> dict:
    """Move a file or directory to a new path."""
    src = normalize_path(source, allow_root=False)
    dest = normalize_path(destination, allow_root=False)
    ensure_allowed_path(src)
    ensure_allowed_path(dest)

    with session_for_user(user_id) as db:
        existing_dest = find_record_by_path(db, user_id, dest)
        if existing_dest:
            raise FileExistsError(f"Destination already exists: {destination}")

        record = find_record_by_path(db, user_id, src)
        if record:
            record.path = dest
            record.filename_original = Path(dest).name
            db.commit()
            return {"source": src, "destination": dest, "type": "file"}

        prefix = f"{src}/"
        records = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.like(f"{prefix}%"),
            )
            .all()
        )
        if not records:
            raise FileNotFoundError(f"Source not found: {source}")

        dest_prefix = f"{dest}/"
        dest_conflict = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.like(f"{dest_prefix}%"),
            )
            .first()
        )
        if dest_conflict:
            raise FileExistsError(f"Destination already exists: {destination}")

        for item in records:
            suffix = item.path[len(prefix):]
            item.path = f"{dest}/{suffix}" if suffix else dest
            item.filename_original = Path(item.path).name

        db.commit()

    return {"source": src, "destination": dest, "type": "directory"}


def _copy_storage_key(user_id: str, source_id: str, target_id: str, storage_key: str) -> str:
    """Build a new storage key for a copied derivative."""
    prefix = f"{user_id}/files/{source_id}/"
    if storage_key.startswith(prefix):
        return f"{user_id}/files/{target_id}/{storage_key[len(prefix):]}"
    return f"{user_id}/files/{target_id}/derivatives/{Path(storage_key).name}"


def _copy_record(
    db,
    storage,
    record: IngestedFile,
    destination: str,
) -> None:
    """Copy a single record and its derivatives to a new destination."""
    now = now_utc()
    new_id = uuid4()
    new_path = destination
    new_filename = Path(new_path).name or record.filename_original

    new_record = IngestedFile(
        id=new_id,
        user_id=record.user_id,
        filename_original=new_filename,
        path=new_path,
        mime_original=record.mime_original,
        size_bytes=record.size_bytes,
        sha256=record.sha256,
        source_url=record.source_url,
        source_metadata=record.source_metadata,
        pinned=record.pinned,
        pinned_order=record.pinned_order,
        created_at=now,
        last_opened_at=None,
        deleted_at=None,
    )
    db.add(new_record)
    db.flush()

    derivatives = (
        db.query(FileDerivative)
        .filter(FileDerivative.file_id == record.id)
        .all()
    )
    if not derivatives:
        job = get_job(db, record.id)
        if job and job.status != "ready":
            raise ValueError(f"File not ready yet (status: {job.status})")
        raise ValueError(f"No copyable content for: {record.path}")

    for item in derivatives:
        new_key = _copy_storage_key(record.user_id, str(record.id), str(new_id), item.storage_key)
        storage.copy_object(item.storage_key, new_key)
        db.add(
            FileDerivative(
                file_id=new_id,
                kind=item.kind,
                storage_key=new_key,
                mime=item.mime,
                size_bytes=item.size_bytes,
                sha256=item.sha256,
                created_at=now,
            )
        )


def copy_path(user_id: str, source: str, destination: str) -> dict:
    """Copy a file or directory to a new path."""
    src = normalize_path(source, allow_root=False)
    dest = normalize_path(destination, allow_root=False)
    ensure_allowed_path(src)
    ensure_allowed_path(dest)

    storage = get_storage_backend()

    with session_for_user(user_id) as db:
        existing_dest = find_record_by_path(db, user_id, dest)
        if existing_dest:
            raise FileExistsError(f"Destination already exists: {destination}")

        record = find_record_by_path(db, user_id, src)
        if record:
            _copy_record(db, storage, record, dest)
            db.commit()
            return {"source": src, "destination": dest, "type": "file"}

        prefix = f"{src}/"
        records = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.like(f"{prefix}%"),
            )
            .all()
        )
        if not records:
            raise FileNotFoundError(f"Source not found: {source}")

        dest_prefix = f"{dest}/"
        dest_conflict = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.like(f"{dest_prefix}%"),
            )
            .first()
        )
        if dest_conflict:
            raise FileExistsError(f"Destination already exists: {destination}")

        for item in records:
            suffix = item.path[len(prefix):]
            target_path = f"{dest}/{suffix}" if suffix else dest
            _copy_record(db, storage, item, target_path)

        db.commit()

    return {"source": src, "destination": dest, "type": "directory"}


def info(user_id: str, path: str) -> dict:
    """Return metadata for a file or directory."""
    normalized = normalize_path(path, allow_root=False)
    ensure_allowed_path(normalized)

    with session_for_user(user_id) as db:
        record = find_record_by_path(db, user_id, normalized)
        if record:
            job = get_job(db, record.id)
            return {
                "path": record.path,
                "size": record.size_bytes,
                "mime": record.mime_original,
                "modified": record.created_at.isoformat() if record.created_at else None,
                "status": job.status if job else None,
                "stage": job.stage if job else None,
                "is_file": True,
                "is_directory": False,
            }

        prefix = f"{normalized}/"
        records = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.path.like(f"{prefix}%"),
            )
            .all()
        )
        if not records:
            raise FileNotFoundError(f"Path not found: {path}")

        latest = max((item.created_at for item in records if item.created_at), default=None)

    return {
        "path": normalized,
        "size": 0,
        "mime": None,
        "modified": latest.isoformat() if latest else None,
        "status": None,
        "stage": None,
        "is_file": False,
        "is_directory": True,
    }
