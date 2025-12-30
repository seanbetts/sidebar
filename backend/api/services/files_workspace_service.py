"""Workspace file operations and storage orchestration."""
from __future__ import annotations

import mimetypes
from datetime import datetime, timezone
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.services.file_tree_service import FileTreeService
from api.services.files_service import FilesService
from api.services.storage.service import get_storage_backend

storage_backend = get_storage_backend()


class FilesWorkspaceService:
    """Workspace-facing file operations backed by storage + DB."""

    @staticmethod
    def get_tree(db: Session, user_id: str, base_path: str) -> dict:
        """Return the file tree for a base path.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder for the tree.

        Returns:
            Tree payload with children.
        """
        base_path = FileTreeService.normalize_base_path(base_path)
        records = FilesService.list_by_prefix(db, user_id, base_path)
        tree = FileTreeService.build_tree(records, base_path)
        return {"children": tree.get("children", [])}

    @staticmethod
    def search(
        db: Session,
        user_id: str,
        query: str,
        base_path: str,
        *,
        limit: int = 50,
    ) -> dict:
        """Search files and format results for the UI.

        Args:
            db: Database session.
            user_id: Current user ID.
            query: Search query string.
            base_path: Base folder to scope the search.
            limit: Max results to return. Defaults to 50.

        Returns:
            Search results payload.
        """
        base_path = FileTreeService.normalize_base_path(base_path)
        records = FilesService.search_by_name(db, user_id, query, base_path, limit=limit)
        items = []
        for record in records:
            rel_path = FileTreeService.relative_path(base_path, record.path)
            items.append(
                {
                    "name": Path(rel_path).name,
                    "path": rel_path,
                    "type": "file",
                    "modified": record.updated_at.timestamp() if record.updated_at else None,
                    "size": record.size,
                }
            )
        return {"items": items}

    @staticmethod
    def create_folder(db: Session, user_id: str, base_path: str, path: str) -> dict:
        """Create a folder marker in storage and metadata.

        Args:
            db: Database session.
            user_id: Current user ID.
            base_path: Base folder path.
            path: Folder path relative to base_path.

        Returns:
            Folder creation result.
        """
        full_path = FileTreeService.full_path(base_path, path)
        bucket_key = FileTreeService.bucket_key(user_id, f"{full_path}/")
        FilesService.upsert_file(
            db,
            user_id,
            full_path,
            bucket_key=bucket_key,
            size=0,
            content_type=None,
            etag=None,
            category="folder",
        )
        return {"success": True}

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
        old_full_path = FileTreeService.full_path(base_path, old_path)
        parent = str(Path(old_path).parent) if Path(old_path).parent != Path(".") else ""
        new_rel = f"{parent}/{new_name}".strip("/")
        new_full_path = FileTreeService.full_path(base_path, new_rel)

        if FilesService.get_by_path(db, user_id, new_full_path):
            raise HTTPException(status_code=400, detail="An item with that name already exists")

        record = FilesService.get_by_path(db, user_id, old_full_path)
        if record:
            is_folder = record.category == "folder"
        else:
            prefix_records = FilesService.list_by_prefix(db, user_id, f"{old_full_path}/")
            if not prefix_records:
                raise HTTPException(status_code=404, detail="Item not found")
            is_folder = True

        if not is_folder:
            old_key = record.bucket_key
            new_key = FileTreeService.bucket_key(user_id, new_full_path)
            storage_backend.move_object(old_key, new_key)
            record.path = new_full_path
            record.bucket_key = new_key
            record.updated_at = datetime.now(timezone.utc)
            db.commit()
            return {"success": True, "newPath": new_rel}

        records = FilesService.list_by_prefix(db, user_id, f"{old_full_path}/")
        for item in records:
            if item.category == "folder":
                item.path = item.path.replace(old_full_path, new_full_path, 1)
                item.bucket_key = FileTreeService.bucket_key(user_id, f"{item.path}/")
                item.updated_at = datetime.now(timezone.utc)
                continue
            old_key = item.bucket_key
            item.path = item.path.replace(old_full_path, new_full_path, 1)
            item.bucket_key = FileTreeService.bucket_key(user_id, item.path)
            item.updated_at = datetime.now(timezone.utc)
            storage_backend.move_object(old_key, item.bucket_key)
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
        full_path = FileTreeService.full_path(base_path, path)
        filename = Path(path).name
        new_full_path = FileTreeService.full_path(base_path, f"{destination}/{filename}")

        if FilesService.get_by_path(db, user_id, new_full_path):
            raise HTTPException(status_code=400, detail="An item with that name already exists")

        record = FilesService.get_by_path(db, user_id, full_path)
        if record:
            is_folder = record.category == "folder"
        else:
            prefix_records = FilesService.list_by_prefix(db, user_id, f"{full_path}/")
            if not prefix_records:
                raise HTTPException(status_code=404, detail="Item not found")
            is_folder = True

        if not is_folder:
            old_key = record.bucket_key
            new_key = FileTreeService.bucket_key(user_id, new_full_path)
            storage_backend.move_object(old_key, new_key)
            record.path = new_full_path
            record.bucket_key = new_key
            record.updated_at = datetime.now(timezone.utc)
            db.commit()
            return {"success": True, "newPath": FileTreeService.relative_path(base_path, new_full_path)}

        records = FilesService.list_by_prefix(db, user_id, f"{full_path}/")
        for item in records:
            if item.category == "folder":
                item.path = item.path.replace(full_path, new_full_path, 1)
                item.bucket_key = FileTreeService.bucket_key(user_id, f"{item.path}/")
                item.updated_at = datetime.now(timezone.utc)
                continue
            old_key = item.bucket_key
            item.path = item.path.replace(full_path, new_full_path, 1)
            item.bucket_key = FileTreeService.bucket_key(user_id, item.path)
            item.updated_at = datetime.now(timezone.utc)
            storage_backend.move_object(old_key, item.bucket_key)
        db.commit()
        return {"success": True, "newPath": FileTreeService.relative_path(base_path, new_full_path)}

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
        full_path = FileTreeService.full_path(base_path, path)
        record = FilesService.get_by_path(db, user_id, full_path)
        if record:
            if record.category != "folder":
                storage_backend.delete_object(record.bucket_key)
            FilesService.mark_deleted(db, user_id, full_path)
            return {"success": True}

        records = FilesService.list_by_prefix(db, user_id, f"{full_path}/")
        if not records:
            raise HTTPException(status_code=404, detail="Item not found")

        for item in records:
            if item.category != "folder":
                storage_backend.delete_object(item.bucket_key)
            FilesService.mark_deleted(db, user_id, item.path)
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
        full_path = FileTreeService.full_path(base_path, path)
        record = FilesService.get_by_path(db, user_id, full_path)
        if not record or record.category == "folder":
            raise HTTPException(status_code=404, detail="File not found")

        content = storage_backend.get_object(record.bucket_key)
        content_type = record.content_type or mimetypes.guess_type(path)[0] or "application/octet-stream"
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
        full_path = FileTreeService.full_path(base_path, path)
        record = FilesService.get_by_path(db, user_id, full_path)
        if not record or record.category == "folder":
            raise HTTPException(status_code=404, detail="File not found")

        content = storage_backend.get_object(record.bucket_key)
        if record.content_type and record.content_type.startswith("text/"):
            decoded = content.decode("utf-8")
        else:
            try:
                decoded = content.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise HTTPException(status_code=400, detail="File is not a text file") from exc

        return {
            "content": decoded,
            "name": Path(path).name,
            "path": path,
            "modified": record.updated_at.timestamp() if record.updated_at else None,
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
        full_path = FileTreeService.full_path(base_path, path)
        bucket_key = FileTreeService.bucket_key(user_id, full_path)
        data = content.encode("utf-8")
        storage_backend.put_object(bucket_key, data, content_type="text/plain")
        record = FilesService.upsert_file(
            db,
            user_id,
            full_path,
            bucket_key=bucket_key,
            size=len(data),
            content_type="text/plain",
            etag=None,
            category="file",
        )
        return {
            "success": True,
            "modified": record.updated_at.timestamp() if record.updated_at else None,
        }
