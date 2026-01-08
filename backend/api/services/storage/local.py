"""Local filesystem storage backend."""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

from api.metrics import storage_operations_total
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

    def list_objects(
        self, prefix: str, recursive: bool = True
    ) -> Iterable[StorageObject]:
        """List local objects under a prefix.

        Args:
            prefix: Prefix to search under.
            recursive: Whether to recurse. Defaults to True.

        Returns:
            Iterable of StorageObject metadata.
        """
        root = self._resolve_key(prefix)
        try:
            if not root.exists():
                storage_operations_total.labels("list", "success").inc()
                return []

            if root.is_file():
                stat = root.stat()
                storage_operations_total.labels("list", "success").inc()
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
            storage_operations_total.labels("list", "success").inc()
            return objects
        except Exception:
            storage_operations_total.labels("list", "error").inc()
            raise

    def get_object(self, key: str) -> bytes:
        """Read object bytes from local storage."""
        try:
            data = self._resolve_key(key).read_bytes()
            storage_operations_total.labels("get", "success").inc()
            return data
        except Exception:
            storage_operations_total.labels("get", "error").inc()
            raise

    def get_object_range(self, key: str, start: int, end: int) -> bytes:
        """Read a byte range from local storage."""
        path = self._resolve_key(key)
        try:
            with path.open("rb") as handle:
                handle.seek(start)
                data = handle.read(end - start + 1)
            storage_operations_total.labels("get_range", "success").inc()
            return data
        except Exception:
            storage_operations_total.labels("get_range", "error").inc()
            raise

    def put_object(
        self, key: str, data: bytes, content_type: str | None = None
    ) -> StorageObject:
        """Write object bytes to local storage."""
        path = self._resolve_key(key)
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            stat = path.stat()
            storage_operations_total.labels("put", "success").inc()
            return StorageObject(
                key=str(path.relative_to(self.base_path)),
                size=stat.st_size,
                content_type=content_type,
                last_modified=None,
            )
        except Exception:
            storage_operations_total.labels("put", "error").inc()
            raise

    def delete_object(self, key: str) -> None:
        """Delete a local object by key."""
        path = self._resolve_key(key)
        try:
            if path.exists():
                path.unlink()
            storage_operations_total.labels("delete", "success").inc()
        except Exception:
            storage_operations_total.labels("delete", "error").inc()
            raise

    def copy_object(self, source_key: str, destination_key: str) -> None:
        """Copy a local object to a new key."""
        source = self._resolve_key(source_key)
        dest = self._resolve_key(destination_key)
        try:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(source.read_bytes())
            storage_operations_total.labels("copy", "success").inc()
        except Exception:
            storage_operations_total.labels("copy", "error").inc()
            raise

    def object_exists(self, key: str) -> bool:
        """Return True if the local object exists."""
        try:
            exists = self._resolve_key(key).exists()
            storage_operations_total.labels("exists", "success").inc()
            return exists
        except Exception:
            storage_operations_total.labels("exists", "error").inc()
            raise
