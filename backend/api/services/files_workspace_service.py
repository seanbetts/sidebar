"""Workspace file operations backed by ingestion."""
from __future__ import annotations

import mimetypes
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.models.file_ingestion import IngestedFile, FileDerivative, FileProcessingJob
from api.services.file_tree_service import FileTreeService
from api.services.storage.service import get_storage_backend
from api.services.skill_file_ops_ingestion import write_text as write_ingested_text
from api.services.workspace_service import WorkspaceService

storage_backend = get_storage_backend()


@dataclass(frozen=True)
class _TreeRecord:
    path: str
    deleted_at: datetime | None
    category: str | None
    size: int
    updated_at: datetime | None


def _full_path(base_path: str, path: str) -> str:
    return FileTreeService.full_path(base_path, path)


def _relative_path(base_path: str, full_path: str) -> str:
    return FileTreeService.relative_path(base_path, full_path)


def _find_record(db: Session, user_id: str, path: str) -> IngestedFile | None:
    return (
        db.query(IngestedFile)
        .filter(
            IngestedFile.user_id == user_id,
            IngestedFile.path == path,
            IngestedFile.deleted_at.is_(None),
        )
        .first()
    )


def _list_prefix(
    db: Session,
    user_id: str,
    prefix: str,
    *,
    include_deleted: bool = False,
) -> list[IngestedFile]:
    prefix_norm = prefix.strip("/")
    query = db.query(IngestedFile).filter(IngestedFile.user_id == user_id)
    if not include_deleted:
        query = query.filter(IngestedFile.deleted_at.is_(None))
    if prefix_norm:
        match = f"{prefix_norm}/%"
        query = query.filter(IngestedFile.path.like(match))
    return query.order_by(IngestedFile.path.asc()).all()


def _pick_download_derivative(db: Session, file_id) -> FileDerivative | None:
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


def _strip_frontmatter(content: str) -> str:
    if not content.startswith("---\n"):
        return content
    marker = "\n---\n"
    idx = content.find(marker)
    if idx == -1:
        return content
    return content[idx + len(marker):]


class FilesWorkspaceService(WorkspaceService[IngestedFile]):
    """Workspace-facing file operations backed by ingestion."""

    @classmethod
    def _query_items(
        cls,
        db: Session,
        user_id: str,
        *,
        include_deleted: bool = False,
        base_path: str = "",
        **kwargs: object,
    ) -> list[IngestedFile]:
        base_path = FileTreeService.normalize_base_path(base_path)
        return _list_prefix(db, user_id, base_path, include_deleted=include_deleted)

    @classmethod
    def _build_tree(cls, items: list[IngestedFile], *, base_path: str = "", **kwargs: object) -> dict:
        base_path = FileTreeService.normalize_base_path(base_path)
        tree_records = [
            _TreeRecord(
                path=record.path,
                deleted_at=record.deleted_at,
                category=None,
                size=record.size_bytes,
                updated_at=record.created_at,
            )
            for record in items
            if record.path
        ]
        tree = FileTreeService.build_tree(tree_records, base_path)
        return tree

    @classmethod
    def _search_items(
        cls,
        db: Session,
        user_id: str,
        query: str,
        *,
        limit: int,
        base_path: str = "",
        **kwargs: object,
    ) -> list[IngestedFile]:
        base_path = FileTreeService.normalize_base_path(base_path)
        like_pattern = f"%{query}%"
        filters = [
            IngestedFile.user_id == user_id,
            IngestedFile.deleted_at.is_(None),
            IngestedFile.path.ilike(like_pattern),
        ]
        if base_path:
            filters.append(IngestedFile.path.like(f"{base_path}/%"))
        records = (
            db.query(IngestedFile)
            .filter(*filters)
            .order_by(IngestedFile.created_at.desc())
            .limit(limit)
            .all()
        )
        return records

    @classmethod
    def _item_to_dict(cls, item: IngestedFile, *, base_path: str = "", **kwargs: object) -> dict:
        base_path = FileTreeService.normalize_base_path(base_path)
        rel_path = _relative_path(base_path, item.path)
        return {
            "name": Path(rel_path).name,
            "path": rel_path,
            "type": "file",
            "modified": item.created_at.timestamp() if item.created_at else None,
            "size": item.size_bytes,
        }

    @classmethod
    def get_tree(cls, db: Session, user_id: str, base_path: str) -> dict:
        """Return the file tree for a base path."""
        return cls.list_tree(db, user_id, base_path=base_path)

    @classmethod
    def search(
        cls,
        db: Session,
        user_id: str,
        query: str,
        base_path: str,
        *,
        limit: int = 50,
    ) -> dict:
        """Search files and format results for the UI."""
        return super().search(db, user_id, query, limit=limit, base_path=base_path)

    @staticmethod
    def create_folder(db: Session, user_id: str, base_path: str, path: str) -> dict:
        """Return success for folder creation (folders are implicit).

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            path: Folder path relative to base_path.

        Returns:
            Folder creation result.
        """
        _full_path(base_path, path)
        return {"success": True, "created": False}

    @staticmethod
    def rename(
        db: Session,
        user_id: str,
        base_path: str,
        old_path: str,
        new_name: str,
    ) -> dict:
        """Rename a file or folder within a base path.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            old_path: Relative path to rename.
            new_name: New name for the item.

        Returns:
            Rename result payload with new path.

        Raises:
            HTTPException: 400 if target exists, 404 if item not found.
        """
        old_full_path = _full_path(base_path, old_path)
        parent = str(Path(old_path).parent) if Path(old_path).parent != Path(".") else ""
        new_rel = f"{parent}/{new_name}".strip("/")
        new_full_path = _full_path(base_path, new_rel)

        if _find_record(db, user_id, new_full_path):
            raise HTTPException(status_code=400, detail="An item with that name already exists")

        record = _find_record(db, user_id, old_full_path)
        if record:
            record.path = new_full_path
            record.filename_original = new_name
            db.commit()
            return {"success": True, "newPath": new_rel}

        prefix_records = _list_prefix(db, user_id, old_full_path)
        if not prefix_records:
            raise HTTPException(status_code=404, detail="Item not found")

        for item in prefix_records:
            item.path = item.path.replace(old_full_path, new_full_path, 1)
            item.filename_original = Path(item.path).name
        db.commit()
        return {"success": True, "newPath": new_rel}

    @staticmethod
    def move(
        db: Session,
        user_id: str,
        base_path: str,
        path: str,
        destination: str,
    ) -> dict:
        """Move a file or folder to a new destination.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            path: Relative path to move.
            destination: Destination folder path.

        Returns:
            Move result payload with new path.

        Raises:
            HTTPException: 400 if target exists, 404 if item not found.
        """
        full_path = _full_path(base_path, path)
        filename = Path(path).name
        new_full_path = _full_path(base_path, f"{destination}/{filename}")

        if _find_record(db, user_id, new_full_path):
            raise HTTPException(status_code=400, detail="An item with that name already exists")

        record = _find_record(db, user_id, full_path)
        if record:
            record.path = new_full_path
            record.filename_original = Path(new_full_path).name
            db.commit()
            return {"success": True, "newPath": _relative_path(base_path, new_full_path)}

        prefix_records = _list_prefix(db, user_id, full_path)
        if not prefix_records:
            raise HTTPException(status_code=404, detail="Item not found")

        for item in prefix_records:
            item.path = item.path.replace(full_path, new_full_path, 1)
            item.filename_original = Path(item.path).name
        db.commit()
        return {"success": True, "newPath": _relative_path(base_path, new_full_path)}

    @staticmethod
    def delete(db: Session, user_id: str, base_path: str, path: str) -> dict:
        """Delete a file or folder.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            path: Relative path to delete.

        Returns:
            Delete result payload.

        Raises:
            HTTPException: 404 if item not found.
        """
        full_path = _full_path(base_path, path)
        record = _find_record(db, user_id, full_path)
        if record:
            job = db.query(FileProcessingJob).filter(FileProcessingJob.file_id == record.id).first()
            if job and job.status not in {"ready", "failed", "canceled"}:
                raise HTTPException(status_code=409, detail="File is still processing")
            derivatives = (
                db.query(FileDerivative)
                .filter(FileDerivative.file_id == record.id)
                .all()
            )
            for item in derivatives:
                storage_backend.delete_object(item.storage_key)
            db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
            record.deleted_at = datetime.now(timezone.utc)
            db.commit()
            return {"success": True}

        records = _list_prefix(db, user_id, full_path)
        if not records:
            raise HTTPException(status_code=404, detail="Item not found")

        for item in records:
            derivatives = (
                db.query(FileDerivative)
                .filter(FileDerivative.file_id == item.id)
                .all()
            )
            for derivative in derivatives:
                storage_backend.delete_object(derivative.storage_key)
            db.query(FileDerivative).filter(FileDerivative.file_id == item.id).delete()
            item.deleted_at = datetime.now(timezone.utc)
        db.commit()
        return {"success": True}

    @staticmethod
    def download(db: Session, user_id: str, base_path: str, path: str) -> dict:
        """Download a file from storage.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            path: Relative file path to download.

        Returns:
            Download payload with bytes and metadata.

        Raises:
            HTTPException: 404 if file not found or is a folder.
        """
        full_path = _full_path(base_path, path)
        record = _find_record(db, user_id, full_path)
        if not record:
            raise HTTPException(status_code=404, detail="File not found")

        derivative = _pick_download_derivative(db, record.id)
        if not derivative:
            raise HTTPException(status_code=404, detail="File data missing")

        content = storage_backend.get_object(derivative.storage_key)
        content_type = derivative.mime or mimetypes.guess_type(path)[0] or "application/octet-stream"
        return {
            "content": content,
            "content_type": content_type,
            "filename": Path(path).name,
        }

    @staticmethod
    def get_content(db: Session, user_id: str, base_path: str, path: str) -> dict:
        """Fetch text content of a file.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            path: Relative file path.

        Returns:
            File content payload.

        Raises:
            HTTPException: 400 if file is not text, 404 if not found.
        """
        full_path = _full_path(base_path, path)
        record = _find_record(db, user_id, full_path)
        if not record:
            raise HTTPException(status_code=404, detail="File not found")

        derivative = (
            db.query(FileDerivative)
            .filter(
                FileDerivative.file_id == record.id,
                FileDerivative.kind.in_(["text_original", "ai_md"]),
            )
            .order_by(FileDerivative.created_at.desc())
            .first()
        )
        if not derivative:
            raise HTTPException(status_code=400, detail="File is not a text file")

        content = storage_backend.get_object(derivative.storage_key)
        try:
            decoded = content.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise HTTPException(status_code=400, detail="File is not a text file") from exc
        if derivative.kind == "ai_md":
            decoded = _strip_frontmatter(decoded)

        return {
            "content": decoded,
            "name": Path(path).name,
            "path": path,
            "modified": record.created_at.timestamp() if record.created_at else None,
        }

    @staticmethod
    def update_content(db: Session, user_id: str, base_path: str, path: str, content: str) -> dict:
        """Write text content to storage and update metadata.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            path: Relative file path.
            content: Text content to store.

        Returns:
            Update result payload with modified timestamp.
        """
        full_path = _full_path(base_path, path)
        write_ingested_text(user_id, full_path, content, mode="replace")
        return {
            "success": True,
            "modified": datetime.now(timezone.utc).timestamp(),
        }
