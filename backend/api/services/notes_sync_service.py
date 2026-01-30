"""Service layer for batched note sync operations."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session

from api.exceptions import BadRequestError, ConflictError, NoteNotFoundError
from api.models.note import Note
from api.services.notes_service import NotesService
from api.utils.timestamps import parse_client_timestamp
from api.utils.validation import parse_uuid


@dataclass
class NotesApplyOutcome:
    """Result summary for applied note operations."""

    applied_ids: list[str]
    notes: list[Note]
    conflicts: list[dict[str, Any]]


@dataclass
class NotesSyncResult:
    """Result summary for note sync operations."""

    applied_ids: list[str]
    notes: list[Note]
    conflicts: list[dict[str, Any]]
    updated_notes: list[Note]
    server_updated_since: datetime


class NotesSyncService:
    """Service for offline note sync and batched operations."""

    @staticmethod
    def sync_operations(
        db: Session, user_id: str, payload: dict[str, Any]
    ) -> NotesSyncResult:
        """Apply operations and return updates since the last sync."""
        last_sync = parse_client_timestamp(
            payload.get("last_sync"), field_name="last_sync"
        )
        operations = payload.get("operations") or []
        if operations and not isinstance(operations, list):
            raise BadRequestError("operations must be a list")

        outcome = NotesSyncService._apply_operations(db, user_id, operations)
        updated_notes = NotesSyncService.list_updates_since(db, user_id, last_sync)
        server_updated_since = NotesSyncService._max_updated_at(
            updated_notes,
            outcome.notes,
        )
        return NotesSyncResult(
            applied_ids=outcome.applied_ids,
            notes=outcome.notes,
            conflicts=outcome.conflicts,
            updated_notes=updated_notes,
            server_updated_since=server_updated_since,
        )

    @staticmethod
    def list_updates_since(
        db: Session, user_id: str, last_sync: datetime | None
    ) -> list[Note]:
        """List notes updated since the provided timestamp."""
        query = db.query(Note).filter(Note.user_id == user_id)
        if last_sync is None:
            query = query.filter(Note.deleted_at.is_(None))
        else:
            query = query.filter(Note.updated_at >= last_sync)
        return query.order_by(Note.updated_at.asc()).all()

    @staticmethod
    def _apply_operations(
        db: Session, user_id: str, operations: list[dict[str, Any]]
    ) -> NotesApplyOutcome:
        """Apply note operations with conflict tracking."""
        applied_ids: list[str] = []
        notes: list[Note] = []
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

            try:
                if op == "create":
                    content = operation.get("content")
                    if content is None:
                        raise BadRequestError("content required")
                    title = operation.get("title") or None
                    folder = (operation.get("folder") or "").strip("/")
                    note_id_value = (
                        operation.get("id")
                        or operation.get("note_id")
                        or operation.get("client_id")
                    )
                    note_id = (
                        parse_uuid(note_id_value, "note", "id")
                        if note_id_value
                        else None
                    )
                    note = NotesService.create_note(
                        db,
                        user_id,
                        str(content),
                        title=title,
                        folder=folder,
                        note_id=note_id,
                    )
                    notes.append(note)
                elif op == "update":
                    note = NotesSyncService._apply_update(
                        db, user_id, operation, client_updated_at
                    )
                    notes.append(note)
                elif op == "rename":
                    note = NotesSyncService._apply_rename(
                        db, user_id, operation, client_updated_at
                    )
                    notes.append(note)
                elif op == "move":
                    note = NotesSyncService._apply_move(
                        db, user_id, operation, client_updated_at
                    )
                    notes.append(note)
                elif op == "pin":
                    note = NotesSyncService._apply_pin(
                        db, user_id, operation, client_updated_at
                    )
                    notes.append(note)
                elif op == "archive":
                    note = NotesSyncService._apply_archive(
                        db, user_id, operation, client_updated_at
                    )
                    notes.append(note)
                elif op == "delete":
                    deleted = NotesSyncService._apply_delete(
                        db, user_id, operation, client_updated_at
                    )
                    if deleted:
                        notes.append(deleted)
                else:
                    pass
            except ConflictError as exc:
                conflict = NotesSyncService._extract_conflict(
                    exc, op=op, operation_id=operation_id
                )
                conflicts.append(conflict)
            except NoteNotFoundError:
                conflicts.append(
                    NotesSyncService._missing_conflict(
                        operation, op=op, operation_id=operation_id
                    )
                )
            finally:
                applied_ids.append(operation_id)

        return NotesApplyOutcome(
            applied_ids=applied_ids,
            notes=notes,
            conflicts=conflicts,
        )

    @staticmethod
    def _apply_update(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Note:
        note_id = NotesSyncService._parse_note_id(operation)
        content = operation.get("content")
        if content is None:
            raise BadRequestError("content required")
        return NotesService.update_note(
            db,
            user_id,
            note_id,
            str(content),
            client_updated_at=client_updated_at,
        )

    @staticmethod
    def _apply_rename(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Note:
        note_id = NotesSyncService._parse_note_id(operation)
        new_name = operation.get("new_name") or operation.get("newName")
        if not new_name:
            raise BadRequestError("new_name required")
        return NotesService.rename_note(
            db,
            user_id,
            note_id,
            Path(str(new_name)).stem,
            client_updated_at=client_updated_at,
        )

    @staticmethod
    def _apply_move(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Note:
        note_id = NotesSyncService._parse_note_id(operation)
        folder = str(operation.get("folder") or "")
        return NotesService.update_folder(
            db,
            user_id,
            note_id,
            folder,
            client_updated_at=client_updated_at,
            op="archive",
        )

    @staticmethod
    def _apply_pin(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Note:
        note_id = NotesSyncService._parse_note_id(operation)
        pinned = bool(operation.get("pinned", False))
        return NotesService.update_pinned(
            db,
            user_id,
            note_id,
            pinned,
            client_updated_at=client_updated_at,
        )

    @staticmethod
    def _apply_archive(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Note:
        note_id = NotesSyncService._parse_note_id(operation)
        archived = bool(operation.get("archived", False))
        folder = "Archive" if archived else ""
        return NotesService.update_folder(
            db,
            user_id,
            note_id,
            folder,
            client_updated_at=client_updated_at,
        )

    @staticmethod
    def _apply_delete(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Note | None:
        note_id = NotesSyncService._parse_note_id(operation)
        return NotesService.soft_delete_note(
            db,
            user_id,
            note_id,
            client_updated_at=client_updated_at,
            allow_missing=True,
        )

    @staticmethod
    def _parse_note_id(operation: dict[str, Any]) -> uuid.UUID:
        note_id_value = operation.get("id")
        if not note_id_value:
            raise BadRequestError("id required")
        return parse_uuid(str(note_id_value), "note", "id")

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
            "serverNote": None,
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
