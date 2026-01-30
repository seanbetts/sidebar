"""Service layer for batched website sync operations."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from sqlalchemy.orm import Session

from api.exceptions import BadRequestError, ConflictError, WebsiteNotFoundError
from api.models.website import Website
from api.services.websites_service import WebsitesService
from api.utils.timestamps import parse_client_timestamp
from api.utils.validation import parse_uuid


@dataclass
class WebsitesApplyOutcome:
    """Result summary for applied website operations."""

    applied_ids: list[str]
    websites: list[Website]
    conflicts: list[dict[str, Any]]


@dataclass
class WebsitesSyncResult:
    """Result summary for website sync operations."""

    applied_ids: list[str]
    websites: list[Website]
    conflicts: list[dict[str, Any]]
    updated_websites: list[Website]
    server_updated_since: datetime


class WebsitesSyncService:
    """Service for offline website sync and batched operations."""

    @staticmethod
    def sync_operations(
        db: Session, user_id: str, payload: dict[str, Any]
    ) -> WebsitesSyncResult:
        """Apply operations and return updates since the last sync."""
        last_sync = parse_client_timestamp(
            payload.get("last_sync"), field_name="last_sync"
        )
        operations = payload.get("operations") or []
        if operations and not isinstance(operations, list):
            raise BadRequestError("operations must be a list")

        outcome = WebsitesSyncService._apply_operations(db, user_id, operations)
        updated_websites = WebsitesSyncService.list_updates_since(
            db, user_id, last_sync
        )
        server_updated_since = WebsitesSyncService._max_updated_at(
            updated_websites,
            outcome.websites,
        )
        return WebsitesSyncResult(
            applied_ids=outcome.applied_ids,
            websites=outcome.websites,
            conflicts=outcome.conflicts,
            updated_websites=updated_websites,
            server_updated_since=server_updated_since,
        )

    @staticmethod
    def list_updates_since(
        db: Session, user_id: str, last_sync: datetime | None
    ) -> list[Website]:
        """List websites updated since the provided timestamp."""
        query = db.query(Website).filter(Website.user_id == user_id)
        if last_sync is None:
            query = query.filter(Website.deleted_at.is_(None))
        else:
            query = query.filter(Website.updated_at >= last_sync)
        return query.order_by(Website.updated_at.asc()).all()

    @staticmethod
    def _apply_operations(
        db: Session, user_id: str, operations: list[dict[str, Any]]
    ) -> WebsitesApplyOutcome:
        """Apply website operations with conflict tracking."""
        applied_ids: list[str] = []
        websites: list[Website] = []
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
                if op == "rename":
                    website = WebsitesSyncService._apply_rename(
                        db, user_id, operation, client_updated_at
                    )
                    websites.append(website)
                elif op == "pin":
                    website = WebsitesSyncService._apply_pin(
                        db, user_id, operation, client_updated_at
                    )
                    websites.append(website)
                elif op == "archive":
                    website = WebsitesSyncService._apply_archive(
                        db, user_id, operation, client_updated_at
                    )
                    websites.append(website)
                elif op == "delete":
                    deleted = WebsitesSyncService._apply_delete(
                        db, user_id, operation, client_updated_at
                    )
                    if deleted:
                        websites.append(deleted)
                else:
                    pass
            except ConflictError as exc:
                conflict = WebsitesSyncService._extract_conflict(
                    exc, op=op, operation_id=operation_id
                )
                conflicts.append(conflict)
            except WebsiteNotFoundError:
                conflicts.append(
                    WebsitesSyncService._missing_conflict(
                        operation, op=op, operation_id=operation_id
                    )
                )
            finally:
                applied_ids.append(operation_id)

        return WebsitesApplyOutcome(
            applied_ids=applied_ids,
            websites=websites,
            conflicts=conflicts,
        )

    @staticmethod
    def _apply_rename(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Website:
        website_id = WebsitesSyncService._parse_website_id(operation)
        title = operation.get("title")
        if not title:
            raise BadRequestError("title required")
        return WebsitesService.update_website(
            db,
            user_id,
            website_id,
            title=str(title),
            client_updated_at=client_updated_at,
        )

    @staticmethod
    def _apply_pin(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Website:
        website_id = WebsitesSyncService._parse_website_id(operation)
        pinned = bool(operation.get("pinned", False))
        return WebsitesService.update_pinned(
            db,
            user_id,
            website_id,
            pinned,
            client_updated_at=client_updated_at,
        )

    @staticmethod
    def _apply_archive(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Website:
        website_id = WebsitesSyncService._parse_website_id(operation)
        archived = bool(operation.get("archived", False))
        return WebsitesService.update_archived(
            db,
            user_id,
            website_id,
            archived,
            client_updated_at=client_updated_at,
        )

    @staticmethod
    def _apply_delete(
        db: Session,
        user_id: str,
        operation: dict[str, Any],
        client_updated_at: datetime | None,
    ) -> Website | None:
        website_id = WebsitesSyncService._parse_website_id(operation)
        return WebsitesService.soft_delete_website(
            db,
            user_id,
            website_id,
            client_updated_at=client_updated_at,
            allow_missing=True,
        )

    @staticmethod
    def _parse_website_id(operation: dict[str, Any]) -> uuid.UUID:
        website_id_value = operation.get("id")
        if not website_id_value:
            raise BadRequestError("id required")
        return parse_uuid(str(website_id_value), "website", "id")

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
            "serverWebsite": None,
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
