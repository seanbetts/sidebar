"""Local filesystem storage backend."""
from __future__ import annotations

from pathlib import Path
from typing import Iterable, Optional

from api.services.storage.base import StorageBackend, StorageObject


class LocalStorage(StorageBackend):
    """Local filesystem-backed storage implementation."""

    def __init__(self, base_path: Path):
        """Initialize the storage backend.

        Args:
            base_path: Root directory for storage.
        """
        self.base_path = base_path

    def _resolve_key(self, key: str) -> Path:
        """Resolve a storage key to a local filesystem path."""
        normalized = key.lstrip("/")
        return self.base_path / normalized

    def list_objects(self, prefix: str, recursive: bool = True) -> Iterable[StorageObject]:
        """List local objects under a prefix.

        Args:
            prefix: Prefix to search under.
            recursive: Whether to recurse. Defaults to True.

        Returns:
            Iterable of StorageObject metadata.
        """
        root = self._resolve_key(prefix)
        if not root.exists():
            return []

        if root.is_file():
            stat = root.stat()
            return [
                StorageObject(
                    key=str(root.relative_to(self.base_path)),
                    size=stat.st_size,
                    last_modified=None,
                )
            ]

        objects = []
        iterator = root.rglob("*") if recursive else root.glob("*")
        for path in iterator:
            if path.is_dir():
                continue
            stat = path.stat()
            objects.append(
                StorageObject(
                    key=str(path.relative_to(self.base_path)),
                    size=stat.st_size,
                    last_modified=None,
                )
            )
        return objects

    def get_object(self, key: str) -> bytes:
        """Read object bytes from local storage."""
        return self._resolve_key(key).read_bytes()

    def get_object_range(self, key: str, start: int, end: int) -> bytes:
        """Read a byte range from local storage."""
        path = self._resolve_key(key)
        with path.open("rb") as handle:
            handle.seek(start)
            return handle.read(end - start + 1)

    def put_object(self, key: str, data: bytes, content_type: Optional[str] = None) -> StorageObject:
        """Write object bytes to local storage."""
        path = self._resolve_key(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        stat = path.stat()
        return StorageObject(
            key=str(path.relative_to(self.base_path)),
            size=stat.st_size,
            content_type=content_type,
            last_modified=None,
        )

    def delete_object(self, key: str) -> None:
        """Delete a local object by key."""
        path = self._resolve_key(key)
        if path.exists():
            path.unlink()

    def copy_object(self, source_key: str, destination_key: str) -> None:
        """Copy a local object to a new key."""
        source = self._resolve_key(source_key)
        dest = self._resolve_key(destination_key)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(source.read_bytes())

    def object_exists(self, key: str) -> bool:
        """Return True if the local object exists."""
        return self._resolve_key(key).exists()
