"""Service layer for batched file sync operations."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from sqlalchemy.orm import Session

from api.exceptions import BadRequestError, ConflictError
from api.models.file_ingestion import IngestedFile
from api.services.file_ingestion_service import FileIngestionService
from api.utils.timestamps import parse_client_timestamp
from api.utils.validation import parse_uuid


@dataclass
class FilesApplyOutcome:
    """Result summary for applied file operations."""

    applied_ids: list[str]
    files: list[IngestedFile]
    conflicts: list[dict[str, Any]]


@dataclass
class FilesSyncResult:
    """Result summary for file sync operations."""

    applied_ids: list[str]
    files: list[IngestedFile]
    conflicts: list[dict[str, Any]]
    updated_files: list[IngestedFile]
    server_updated_since: datetime


class FilesSyncService:
    """Service for offline file sync and batched operations."""

    @staticmethod
    def sync_operations(
        db: Session, user_id: str, payload: dict[str, Any]
    ) -> FilesSyncResult:
        """Apply operations and return updates since the last sync."""
        last_sync = parse_client_timestamp(
            payload.get("last_sync"), field_name="last_sync"
        )
        operations = payload.get("operations") or []
        if operations and not isinstance(operations, list):
            raise BadRequestError("operations must be a list")

        outcome = FilesSyncService._apply_operations(db, user_id, operations)
        updated_files = FilesSyncService.list_updates_since(db, user_id, last_sync)
        server_updated_since = FilesSyncService._max_updated_at(
            updated_files,
            outcome.files,
        )
        return FilesSyncResult(
            applied_ids=outcome.applied_ids,
            files=outcome.files,
            conflicts=outcome.conflicts,
            updated_files=updated_files,
            server_updated_since=server_updated_since,
        )

    @staticmethod
    def list_updates_since(
        db: Session, user_id: str, last_sync: datetime | None
    ) -> list[IngestedFile]:
        """List files updated since the provided timestamp."""
        return FileIngestionService.list_ingestions(
            db,
            user_id,
            limit=None,
            include_deleted=last_sync is not None,
            updated_after=last_sync,
        )

    @staticmethod
    def _apply_operations(
        db: Session, user_id: str, operations: list[dict[str, Any]]
    ) -> FilesApplyOutcome:
        """Apply file operations with conflict tracking."""
        applied_ids: list[str] = []
        files: list[IngestedFile] = []
        conflicts: list[dict[str, Any]] = []

        for operation in operations:
            operation_id = str(operation.get("operation_id") or "").strip()
            if not operation_id:
                operation_id = str(uuid.uuid4())
            op = str(operation.get("op") or "").strip()
            if not op:
                continue

            client_updated_at = parse_client_timestamp(
                operation.get("client_updated_at"), field_name="client_updated_at"
            )
            record = None
            if op in {"rename", "pin", "delete"}:
                record = FileIngestionService.get_file(
                    db,
                    user_id,
                    FilesSyncService._parse_file_id(operation),
                    include_deleted=True,
                )
                if not record and op != "delete":
                    conflicts.append(
                        FilesSyncService._missing_conflict(
                            operation, op=op, operation_id=operation_id
                        )
                    )
                    applied_ids.append(operation_id)
                    continue
                if record and record.deleted_at is not None and op != "delete":
                    conflicts.append(
                        FilesSyncService._missing_conflict(
                            operation, op=op, operation_id=operation_id
                        )
                    )
                    applied_ids.append(operation_id)
                    continue
                if op == "delete" and (record is None or record.deleted_at is not None):
                    applied_ids.append(operation_id)
                    continue

            try:
                if op == "rename":
                    record = FilesSyncService._apply_rename(
                        db, user_id, operation, client_updated_at
                    )
                    files.append(record)
                elif op == "pin":
                    record = FilesSyncService._apply_pin(
                        db, user_id, operation, client_updated_at
                    )
                    files.append(record)
                elif op == "delete":
                    record = FilesSyncService._apply_delete(
                        db, user_id, operation, client_updated_at
                    )
                    if record:
                        files.append(record)
                else:
                    pass
            except ConflictError as exc:
                conflict = FilesSyncService._extract_conflict(
                    exc, op=op, operation_id=operation_id
                )
                conflicts.append(conflict)
            finally:
                applied_ids.append(operation_id)

        return FilesApplyOutcome(
            applied_ids=applied_ids,
            files=files,
            conflicts=conflicts,
        )

    @staticmethod
    def _apply_rename(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> IngestedFile:
        file_id = FilesSyncService._parse_file_id(operation)
        filename = operation.get("filename") or operation.get("filename_original")
        if not filename:
            raise BadRequestError("filename is required")
        FileIngestionService.update_filename(
            db,
            user_id,
            file_id,
            str(filename),
            client_updated_at=client_updated_at,
        )
        record = FileIngestionService.get_file(
            db, user_id, file_id, include_deleted=True
        )
        if not record:
            raise BadRequestError("File not found")
        return record

    @staticmethod
    def _apply_pin(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> IngestedFile:
        file_id = FilesSyncService._parse_file_id(operation)
        pinned = bool(operation.get("pinned", False))
        FileIngestionService.update_pinned(
            db,
            user_id,
            file_id,
            pinned,
            client_updated_at=client_updated_at,
        )
        record = FileIngestionService.get_file(
            db, user_id, file_id, include_deleted=True
        )
        if not record:
            raise BadRequestError("File not found")
        return record

    @staticmethod
    def _apply_delete(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> IngestedFile | None:
        file_id = FilesSyncService._parse_file_id(operation)
        deleted = FileIngestionService.delete_file(
            db,
            user_id,
            file_id,
            allow_missing=True,
            client_updated_at=client_updated_at,
        )
        if not deleted:
            return None
        return FileIngestionService.get_file(db, user_id, file_id, include_deleted=True)

    @staticmethod
    def _parse_file_id(operation: dict[str, Any]) -> uuid.UUID:
        file_id_value = operation.get("id")
        if not file_id_value:
            raise BadRequestError("id required")
        return parse_uuid(str(file_id_value), "file", "id")

    @staticmethod
    def _extract_conflict(
        exc: ConflictError, *, op: str, operation_id: str
    ) -> dict[str, Any]:
        payload = dict(exc.details.get("conflict") or {})
        payload.setdefault("operationId", operation_id)
        payload.setdefault("op", op)
        payload.setdefault("reason", "stale")
        return payload

    @staticmethod
    def _missing_conflict(
        operation: dict[str, Any], *, op: str, operation_id: str
    ) -> dict[str, Any]:
        return {
            "operationId": operation_id,
            "op": op,
            "id": operation.get("id"),
            "clientUpdatedAt": None,
            "serverUpdatedAt": None,
            "serverFile": None,
            "reason": "not_found",
        }

    @staticmethod
    def _max_updated_at(*collections: list[Any]) -> datetime:
        latest: datetime | None = None
        for collection in collections:
            for item in collection:
                updated_at = getattr(item, "updated_at", None)
                if updated_at and (latest is None or updated_at > latest):
                    latest = updated_at
        return latest or datetime.now(UTC)
