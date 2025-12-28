"""Storage backend interfaces and data structures."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Iterable, Optional


@dataclass(frozen=True)
class StorageObject:
    """Metadata for a stored object."""

    key: str
    size: int
    etag: Optional[str] = None
    content_type: Optional[str] = None
    last_modified: Optional[datetime] = None


class StorageBackend:
    """Interface for storage backends."""

    def list_objects(self, prefix: str, recursive: bool = True) -> Iterable[StorageObject]:
        """List objects under a prefix.

        Args:
            prefix: Prefix to search under.
            recursive: Whether to list recursively. Defaults to True.

        Returns:
            Iterable of StorageObject metadata.
        """
        raise NotImplementedError

    def get_object(self, key: str) -> bytes:
        """Retrieve object bytes by key.

        Args:
            key: Object key.

        Returns:
            Object bytes.
        """
        raise NotImplementedError

    def put_object(self, key: str, data: bytes, content_type: Optional[str] = None) -> StorageObject:
        """Store object bytes under a key.

        Args:
            key: Object key.
            data: Object bytes.
            content_type: Optional MIME type.

        Returns:
            Stored object metadata.
        """
        raise NotImplementedError

    def delete_object(self, key: str) -> None:
        """Delete an object by key.

        Args:
            key: Object key.
        """
        raise NotImplementedError

    def copy_object(self, source_key: str, destination_key: str) -> None:
        """Copy an object to a new key.

        Args:
            source_key: Source object key.
            destination_key: Destination object key.
        """
        raise NotImplementedError

    def move_object(self, source_key: str, destination_key: str) -> None:
        """Move an object to a new key.

        Args:
            source_key: Source object key.
            destination_key: Destination object key.
        """
        self.copy_object(source_key, destination_key)
        self.delete_object(source_key)

    def object_exists(self, key: str) -> bool:
        """Check whether an object exists.

        Args:
            key: Object key.

        Returns:
            True if the object exists.
        """
        raise NotImplementedError
