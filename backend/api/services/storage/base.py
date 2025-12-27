"""Storage backend interfaces and data structures."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Iterable, Optional


@dataclass(frozen=True)
class StorageObject:
    key: str
    size: int
    etag: Optional[str] = None
    content_type: Optional[str] = None
    last_modified: Optional[datetime] = None


class StorageBackend:
    def list_objects(self, prefix: str, recursive: bool = True) -> Iterable[StorageObject]:
        raise NotImplementedError

    def get_object(self, key: str) -> bytes:
        raise NotImplementedError

    def put_object(self, key: str, data: bytes, content_type: Optional[str] = None) -> StorageObject:
        raise NotImplementedError

    def delete_object(self, key: str) -> None:
        raise NotImplementedError

    def copy_object(self, source_key: str, destination_key: str) -> None:
        raise NotImplementedError

    def move_object(self, source_key: str, destination_key: str) -> None:
        self.copy_object(source_key, destination_key)
        self.delete_object(source_key)

    def object_exists(self, key: str) -> bool:
        raise NotImplementedError
