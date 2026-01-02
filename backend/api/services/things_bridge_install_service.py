"""Install token helpers for Things bridge."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import secrets
from typing import Optional

from sqlalchemy.orm import Session

from api.models.things_bridge_install_token import ThingsBridgeInstallToken


class ThingsBridgeInstallService:
    """Create and validate one-time install tokens."""

    @staticmethod
    def _hash_token(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    @staticmethod
    def create_token(db: Session, user_id: str, ttl_minutes: int = 15) -> dict:
        token = f"tb_inst_{secrets.token_urlsafe(32)}"
        token_hash = ThingsBridgeInstallService._hash_token(token)
        now = datetime.now(timezone.utc)
        record = ThingsBridgeInstallToken(
            user_id=user_id,
            token_hash=token_hash,
            expires_at=now + timedelta(minutes=ttl_minutes),
            used_at=None,
            created_at=now,
        )
        db.add(record)
        db.commit()
        db.refresh(record)
        return {
            "token": token,
            "expires_at": record.expires_at,
            "id": record.id,
        }

    @staticmethod
    def consume_token(db: Session, token: str) -> Optional[ThingsBridgeInstallToken]:
        token_hash = ThingsBridgeInstallService._hash_token(token)
        record = (
            db.query(ThingsBridgeInstallToken)
            .filter(ThingsBridgeInstallToken.token_hash == token_hash)
            .first()
        )
        if not record:
            return None
        now = datetime.now(timezone.utc)
        if record.used_at is not None:
            return None
        if record.expires_at < now:
            return None
        record.used_at = now
        db.commit()
        db.refresh(record)
        return record
