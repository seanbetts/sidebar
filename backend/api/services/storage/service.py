"""Storage backend factory."""

from __future__ import annotations

from pathlib import Path

from api.config import settings
from api.services.storage.base import StorageBackend
from api.services.storage.local import LocalStorage
from api.services.storage.r2 import R2Storage


def get_storage_backend() -> StorageBackend:
    """Return the configured storage backend.

    Returns:
        StorageBackend implementation based on settings.
    """
    backend = settings.storage_backend.lower()
    if backend == "r2":
        access_key_id = settings.r2_access_key_id or settings.r2_access_key
        return R2Storage(
            endpoint=settings.r2_endpoint,
            bucket=settings.r2_bucket,
            access_key_id=access_key_id,
            secret_access_key=settings.r2_secret_access_key,
        )

    return LocalStorage(Path(settings.workspace_base))
