"""Service layer for device token registration."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from api.exceptions import BadRequestError
from api.models.device_token import DeviceToken


class DeviceTokenService:
    """Service for managing device tokens."""

    VALID_PLATFORMS = {"ios", "macos"}
    VALID_ENVIRONMENTS = {"dev", "prod"}

    @staticmethod
    def normalize_environment(environment: str) -> str:
        """Normalize environment labels to dev/prod."""
        env = str(environment or "").strip().lower()
        if env in {"production", "prod"}:
            return "prod"
        if env in {"development", "dev", "sandbox"}:
            return "dev"
        return env

    @staticmethod
    def normalize_capabilities(capabilities: Any) -> dict[str, bool]:
        """Normalize a device capability payload."""
        if capabilities is None:
            return {}
        if not isinstance(capabilities, dict):
            raise BadRequestError("capabilities must be an object")

        normalized: dict[str, bool] = {}
        for raw_key, raw_value in capabilities.items():
            key = str(raw_key or "").strip()
            if not key:
                raise BadRequestError("capability names must be non-empty strings")
            if not isinstance(raw_value, bool):
                raise BadRequestError("capability values must be booleans")
            normalized[key] = raw_value
        return normalized

    @staticmethod
    def _apply_registration_state(
        record: DeviceToken,
        *,
        user_id: str,
        platform: str,
        environment: str,
        capabilities: dict[str, bool],
        now: datetime,
    ) -> None:
        """Apply the latest registration state to a token record."""
        record.user_id = user_id
        record.platform = platform
        record.environment = environment
        record.capabilities = capabilities
        record.disabled_at = None
        record.updated_at = now

    @staticmethod
    def _is_duplicate_token_integrity_error(error: IntegrityError) -> bool:
        """Return whether an integrity error came from the unique token constraint."""
        diag = getattr(error.orig, "diag", None)
        constraint_name = getattr(diag, "constraint_name", None)
        return constraint_name == "uq_device_tokens_token" or (
            "uq_device_tokens_token" in str(error.orig)
        )

    @staticmethod
    def register_token(
        db: Session,
        user_id: str,
        *,
        token: str,
        platform: str,
        environment: str,
        capabilities: Any = None,
    ) -> DeviceToken:
        """Register or update a device token.

        Args:
            db: Database session.
            user_id: Current user ID.
            token: APNs device token.
            platform: Device platform (ios/macos).
            environment: Push environment (dev/prod).
            capabilities: Optional device capability flags.

        Returns:
            Upserted device token record.
        """
        token = str(token or "").strip()
        platform = str(platform or "").strip().lower()
        environment = DeviceTokenService.normalize_environment(environment)
        normalized_capabilities = DeviceTokenService.normalize_capabilities(
            capabilities
        )

        if not token:
            raise BadRequestError("token required")
        if platform not in DeviceTokenService.VALID_PLATFORMS:
            raise BadRequestError("platform must be ios or macos")
        if environment not in DeviceTokenService.VALID_ENVIRONMENTS:
            raise BadRequestError("environment must be dev or prod")

        now = datetime.now(UTC)
        record = db.query(DeviceToken).filter(DeviceToken.token == token).one_or_none()
        if record:
            DeviceTokenService._apply_registration_state(
                record,
                user_id=user_id,
                platform=platform,
                environment=environment,
                capabilities=normalized_capabilities,
                now=now,
            )
            db.flush()
            return record

        record = DeviceToken(
            user_id=user_id,
            token=token,
            platform=platform,
            environment=environment,
            capabilities=normalized_capabilities,
            is_foreground=False,
            last_seen_at=None,
            created_at=now,
            updated_at=now,
        )
        savepoint = db.begin_nested()
        try:
            db.add(record)
            db.flush()
            savepoint.commit()
        except IntegrityError as exc:
            savepoint.rollback()
            if not DeviceTokenService._is_duplicate_token_integrity_error(exc):
                raise
            record = db.query(DeviceToken).filter(DeviceToken.token == token).one()
            DeviceTokenService._apply_registration_state(
                record,
                user_id=user_id,
                platform=platform,
                environment=environment,
                capabilities=normalized_capabilities,
                now=now,
            )
            db.flush()
        return record

    @staticmethod
    def update_presence(
        db: Session,
        user_id: str,
        *,
        token: str,
        is_foreground: bool,
        last_seen_at: datetime | None,
    ) -> DeviceToken | None:
        """Update token presence metadata for the current user."""
        token = str(token or "").strip()
        if not token:
            raise BadRequestError("token required")

        record = (
            db.query(DeviceToken)
            .filter(DeviceToken.user_id == user_id, DeviceToken.token == token)
            .one_or_none()
        )
        if not record:
            return None

        record.is_foreground = is_foreground
        record.last_seen_at = last_seen_at
        record.updated_at = datetime.now(UTC)
        db.flush()
        return record

    @staticmethod
    def disable_token(db: Session, user_id: str, token: str) -> DeviceToken | None:
        """Disable a device token for a user.

        Args:
            db: Database session.
            user_id: Current user ID.
            token: APNs device token.

        Returns:
            Updated device token or None if not found.
        """
        token = str(token or "").strip()
        if not token:
            raise BadRequestError("token required")

        record = (
            db.query(DeviceToken)
            .filter(DeviceToken.user_id == user_id, DeviceToken.token == token)
            .one_or_none()
        )
        if not record:
            return None

        record.disabled_at = datetime.now(UTC)
        record.updated_at = datetime.now(UTC)
        db.flush()
        return record

    @staticmethod
    def disable_tokens_by_value(db: Session, tokens: list[str]) -> int:
        """Disable a batch of device tokens by value."""
        cleaned = [token.strip() for token in tokens if token and token.strip()]
        if not cleaned:
            return 0
        now = datetime.now(UTC)
        records = db.query(DeviceToken).filter(DeviceToken.token.in_(cleaned)).all()
        for record in records:
            record.disabled_at = now
            record.updated_at = now
        db.flush()
        return len(records)

    @staticmethod
    def list_active_tokens(
        db: Session,
        user_id: str,
        *,
        platform: str | None = None,
        environment: str | None = None,
    ) -> list[DeviceToken]:
        """List active device tokens for a user.

        Args:
            db: Database session.
            user_id: Current user ID.
            platform: Optional platform filter.
            environment: Optional environment filter.

        Returns:
            Active device tokens.
        """
        query = db.query(DeviceToken).filter(
            DeviceToken.user_id == user_id,
            DeviceToken.disabled_at.is_(None),
        )
        if platform:
            query = query.filter(DeviceToken.platform == platform)
        if environment:
            query = query.filter(DeviceToken.environment == environment)
        return query.order_by(DeviceToken.created_at.desc()).all()
