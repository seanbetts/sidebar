"""File metadata service for storage objects."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from api.models.file_object import FileObject


class FilesService:
    @staticmethod
    def upsert_file(
        db: Session,
        user_id: str,
        path: str,
        *,
        bucket_key: str,
        size: int,
        content_type: Optional[str] = None,
        etag: Optional[str] = None,
        category: Optional[str] = None,
    ) -> FileObject:
        """Create or update a file metadata record.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Logical file path.
            bucket_key: Storage bucket key.
            size: File size in bytes.
            content_type: Optional MIME type.
            etag: Optional storage etag.
            category: Optional category label.

        Returns:
            Upserted FileObject record.
        """
        now = datetime.now(timezone.utc)
        record = (
            db.query(FileObject)
            .filter(
                FileObject.user_id == user_id,
                FileObject.path == path,
            )
            .first()
        )
        if record:
            record.bucket_key = bucket_key
            record.size = size
            record.content_type = content_type
            record.etag = etag
            record.category = category
            record.deleted_at = None
            record.updated_at = now
        else:
            record = FileObject(
                user_id=user_id,
                path=path,
                bucket_key=bucket_key,
                size=size,
                content_type=content_type,
                etag=etag,
                category=category,
                created_at=now,
                updated_at=now,
                deleted_at=None,
            )
            db.add(record)

        db.flush()
        db.commit()
        return record

    @staticmethod
    def get_by_path(db: Session, user_id: str, path: str) -> Optional[FileObject]:
        """Fetch a non-deleted file record by path.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Logical file path.

        Returns:
            FileObject if found, otherwise None.
        """
        return (
            db.query(FileObject)
            .filter(
                FileObject.user_id == user_id,
                FileObject.path == path,
                FileObject.deleted_at.is_(None),
            )
            .first()
        )

    @staticmethod
    def get_any_by_path(db: Session, user_id: str, path: str) -> Optional[FileObject]:
        """Fetch a file record by path, including deleted.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Logical file path.

        Returns:
            FileObject if found, otherwise None.
        """
        return (
            db.query(FileObject)
            .filter(
                FileObject.user_id == user_id,
                FileObject.path == path,
            )
            .first()
        )

    @staticmethod
    def delete_any_by_path(db: Session, user_id: str, path: str) -> bool:
        """Hard delete a file record by path.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Logical file path.

        Returns:
            True if a record was deleted, False otherwise.
        """
        deleted = (
            db.query(FileObject)
            .filter(
                FileObject.user_id == user_id,
                FileObject.path == path,
            )
            .delete(synchronize_session=False)
        )
        if not deleted:
            return False
        db.commit()
        return True

    @staticmethod
    def list_by_prefix(db: Session, user_id: str, prefix: str) -> list[FileObject]:
        """List files under a prefix.

        Args:
            db: Database session.
            user_id: Current user ID.
            prefix: Prefix path to list under.

        Returns:
            Sorted list of FileObject records.
        """
        prefix_norm = prefix.strip("/")
        if prefix_norm:
            match = f"{prefix_norm}%"
            query = db.query(FileObject).filter(
                FileObject.user_id == user_id,
                FileObject.deleted_at.is_(None),
                FileObject.path.like(match),
            )
        else:
            query = db.query(FileObject).filter(
                FileObject.user_id == user_id,
                FileObject.deleted_at.is_(None),
            )
        return query.order_by(FileObject.path.asc()).all()

    @staticmethod
    def search_by_name(
        db: Session,
        user_id: str,
        query: str,
        base_prefix: str,
        *,
        limit: int = 50,
    ) -> list[FileObject]:
        """Search files by name substring.

        Args:
            db: Database session.
            user_id: Current user ID.
            query: Substring to match.
            base_prefix: Optional prefix filter.
            limit: Max results to return. Defaults to 50.

        Returns:
            List of matching FileObject records.
        """
        prefix_norm = base_prefix.strip("/")
        like_pattern = f"%{query}%"
        q = (
            db.query(FileObject)
            .filter(
                FileObject.user_id == user_id,
                FileObject.deleted_at.is_(None),
                FileObject.path.ilike(like_pattern),
            )
            .order_by(FileObject.updated_at.desc())
            .limit(limit)
        )
        if prefix_norm:
            q = q.filter(FileObject.path.like(f"{prefix_norm}%"))
        return q.all()

    @staticmethod
    def mark_deleted(db: Session, user_id: str, path: str) -> bool:
        """Soft delete a file record by path.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Logical file path.

        Returns:
            True if the record was marked deleted, False otherwise.
        """
        record = (
            db.query(FileObject)
            .filter(
                FileObject.user_id == user_id,
                FileObject.path == path,
                FileObject.deleted_at.is_(None),
            )
            .first()
        )
        if not record:
            return False
        record.deleted_at = datetime.now(timezone.utc)
        record.updated_at = datetime.now(timezone.utc)
        db.commit()
        return True

    @staticmethod
    def move_path(db: Session, user_id: str, old_path: str, new_path: str) -> bool:
        """Update a file record's path.

        Args:
            db: Database session.
            user_id: Current user ID.
            old_path: Existing file path.
            new_path: New file path.

        Returns:
            True if updated, False if not found.
        """
        record = (
            db.query(FileObject)
            .filter(
                FileObject.user_id == user_id,
                FileObject.path == old_path,
                FileObject.deleted_at.is_(None),
            )
            .first()
        )
        if not record:
            return False
        record.path = new_path
        record.updated_at = datetime.now(timezone.utc)
        db.commit()
        return True
