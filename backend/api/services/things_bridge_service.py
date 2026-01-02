"""Service helpers for Things bridge registry."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from typing import Optional
import uuid

from sqlalchemy.orm import Session

from api.config import settings
from api.models.things_bridge import ThingsBridge


class ThingsBridgeService:
    """CRUD helpers for Things bridge registry."""

    @staticmethod
    def register_bridge(
        db: Session,
        user_id: str,
        *,
        device_id: str,
        device_name: str,
        base_url: str,
        capabilities: Optional[dict] = None,
    ) -> ThingsBridge:
        """Register or update a Things bridge for a user."""
        now = datetime.now(timezone.utc)
        bridge = (
            db.query(ThingsBridge)
            .filter(
                ThingsBridge.user_id == user_id,
                ThingsBridge.device_id == device_id,
            )
            .first()
        )
        if bridge:
            bridge.device_name = device_name
            bridge.base_url = base_url
            bridge.capabilities = capabilities or bridge.capabilities
            bridge.last_seen_at = now
            bridge.updated_at = now
        else:
            bridge = ThingsBridge(
                user_id=user_id,
                device_id=device_id,
                device_name=device_name,
                base_url=base_url,
                bridge_token=secrets.token_urlsafe(32),
                capabilities=capabilities,
                last_seen_at=now,
                created_at=now,
                updated_at=now,
            )
            db.add(bridge)
        db.commit()
        db.refresh(bridge)
        return bridge

    @staticmethod
    def heartbeat(db: Session, user_id: str, bridge_id: uuid.UUID) -> Optional[ThingsBridge]:
        """Update last_seen_at for a bridge."""
        bridge = (
            db.query(ThingsBridge)
            .filter(
                ThingsBridge.id == bridge_id,
                ThingsBridge.user_id == user_id,
            )
            .first()
        )
        if not bridge:
            return None
        now = datetime.now(timezone.utc)
        bridge.last_seen_at = now
        bridge.updated_at = now
        db.commit()
        db.refresh(bridge)
        return bridge

    @staticmethod
    def list_bridges(db: Session, user_id: str) -> list[ThingsBridge]:
        """List bridges for a user."""
        return (
            db.query(ThingsBridge)
            .filter(ThingsBridge.user_id == user_id)
            .order_by(ThingsBridge.last_seen_at.desc())
            .all()
        )

    @staticmethod
    def select_active_bridge(db: Session, user_id: str) -> Optional[ThingsBridge]:
        """Pick the most recently seen bridge within the staleness window."""
        cutoff = datetime.now(timezone.utc) - timedelta(seconds=settings.things_bridge_stale_seconds)
        return (
            db.query(ThingsBridge)
            .filter(
                ThingsBridge.user_id == user_id,
                ThingsBridge.last_seen_at >= cutoff,
            )
            .order_by(ThingsBridge.last_seen_at.desc())
            .first()
        )
