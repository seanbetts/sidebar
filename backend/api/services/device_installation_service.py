"""Service layer for push-capable app installations and user bindings."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import or_
from sqlalchemy.orm import Session

from api.exceptions import BadRequestError
from api.models.device_installation import DeviceInstallation, DeviceInstallationUser


class DeviceInstallationService:
    """Manage app installations independently from user bindings."""

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
    def get_installation(
        db: Session,
        *,
        installation_id: str,
    ) -> DeviceInstallation | None:
        """Return the latest installation row for a logical installation id."""
        return (
            db.query(DeviceInstallation)
            .filter(DeviceInstallation.installation_id == installation_id)
            .order_by(
                DeviceInstallation.disabled_at.is_(None).desc(),
                DeviceInstallation.updated_at.desc(),
            )
            .one_or_none()
        )

    @staticmethod
    def list_bindings(
        db: Session,
        *,
        installation_id: str,
    ) -> list[DeviceInstallationUser]:
        """Return historical bindings for an installation ordered by bind time."""
        return (
            db.query(DeviceInstallationUser)
            .join(
                DeviceInstallation,
                DeviceInstallation.id == DeviceInstallationUser.installation_pk,
            )
            .filter(DeviceInstallation.installation_id == installation_id)
            .order_by(
                DeviceInstallationUser.bound_at.asc(),
                DeviceInstallationUser.created_at.asc(),
            )
            .all()
        )

    @staticmethod
    def register_installation(
        db: Session,
        user_id: str,
        *,
        installation_id: str,
        token: str,
        platform: str,
        environment: str,
        capabilities: Any = None,
    ) -> DeviceInstallation:
        """Upsert an installation and bind it to the currently signed-in user."""
        installation_id = str(installation_id or "").strip()
        token = str(token or "").strip()
        platform = str(platform or "").strip().lower()
        environment = DeviceInstallationService.normalize_environment(environment)
        normalized_capabilities = DeviceInstallationService.normalize_capabilities(
            capabilities
        )

        if not installation_id:
            raise BadRequestError("installation_id required")
        if not token:
            raise BadRequestError("token required")
        if platform not in DeviceInstallationService.VALID_PLATFORMS:
            raise BadRequestError("platform must be ios or macos")
        if environment not in DeviceInstallationService.VALID_ENVIRONMENTS:
            raise BadRequestError("environment must be dev or prod")

        now = datetime.now(UTC)
        installation_by_id = DeviceInstallationService._find_active_installation_by_id(
            db,
            installation_id=installation_id,
        )
        installation_by_token = (
            DeviceInstallationService._find_active_installation_by_token(
                db, token=token
            )
        )

        canonical = installation_by_id or installation_by_token
        if (
            installation_by_id
            and installation_by_token
            and installation_by_id.id != installation_by_token.id
        ):
            DeviceInstallationService._disable_installation_row(
                db,
                installation_by_token,
                now=now,
            )
            canonical = installation_by_id

        if canonical is None:
            canonical = DeviceInstallation(
                installation_id=installation_id,
                token=token,
                platform=platform,
                environment=environment,
                capabilities=normalized_capabilities,
                is_foreground=False,
                last_seen_at=None,
                created_at=now,
                updated_at=now,
                disabled_at=None,
            )
            db.add(canonical)
            db.flush()
        else:
            canonical.installation_id = installation_id
            canonical.token = token
            canonical.platform = platform
            canonical.environment = environment
            canonical.capabilities = normalized_capabilities
            canonical.disabled_at = None
            canonical.updated_at = now
            db.flush()

        DeviceInstallationService._bind_installation_to_user(
            db,
            installation_pk=canonical.id,
            user_id=user_id,
            now=now,
        )
        db.flush()
        return canonical

    @staticmethod
    def disable_installation(
        db: Session,
        user_id: str,
        *,
        installation_id: str | None = None,
        token: str | None = None,
    ) -> bool:
        """Unbind the current user from one installation without deleting it."""
        installation = DeviceInstallationService._find_bound_installation(
            db,
            user_id=user_id,
            installation_id=installation_id,
            token=token,
        )
        if installation is None:
            return False

        now = datetime.now(UTC)
        bindings = (
            db.query(DeviceInstallationUser)
            .filter(
                DeviceInstallationUser.installation_pk == installation.id,
                DeviceInstallationUser.user_id == user_id,
                DeviceInstallationUser.unbound_at.is_(None),
            )
            .all()
        )
        if not bindings:
            return False

        for binding in bindings:
            binding.unbound_at = now
            binding.updated_at = now
        installation.is_foreground = False
        installation.updated_at = now
        db.flush()
        return True

    @staticmethod
    def update_presence(
        db: Session,
        user_id: str,
        *,
        installation_id: str | None = None,
        token: str | None = None,
        is_foreground: bool,
        last_seen_at: datetime | None,
    ) -> DeviceInstallation | None:
        """Update foreground and activity metadata for the current user's install."""
        installation = DeviceInstallationService._find_bound_installation(
            db,
            user_id=user_id,
            installation_id=installation_id,
            token=token,
        )
        if installation is None:
            return None

        installation.is_foreground = is_foreground
        installation.last_seen_at = last_seen_at
        installation.updated_at = datetime.now(UTC)
        db.flush()
        return installation

    @staticmethod
    def disable_tokens_by_value(db: Session, tokens: list[str]) -> int:
        """Disable installations by APNs token and end any active bindings."""
        cleaned = [token.strip() for token in tokens if token and token.strip()]
        if not cleaned:
            return 0

        now = datetime.now(UTC)
        installations = (
            db.query(DeviceInstallation)
            .filter(
                DeviceInstallation.token.in_(cleaned),
                DeviceInstallation.disabled_at.is_(None),
            )
            .all()
        )
        for installation in installations:
            DeviceInstallationService._disable_installation_row(
                db,
                installation,
                now=now,
            )
        db.flush()
        return len(installations)

    @staticmethod
    def list_active_tokens(
        db: Session,
        user_id: str,
        *,
        platform: str | None = None,
        environment: str | None = None,
    ) -> list[DeviceInstallation]:
        """List active installations currently bound to a user."""
        query = (
            db.query(DeviceInstallation)
            .join(
                DeviceInstallationUser,
                DeviceInstallationUser.installation_pk == DeviceInstallation.id,
            )
            .filter(
                DeviceInstallationUser.user_id == user_id,
                DeviceInstallationUser.unbound_at.is_(None),
                DeviceInstallation.disabled_at.is_(None),
            )
        )
        if platform:
            query = query.filter(DeviceInstallation.platform == platform)
        if environment:
            query = query.filter(DeviceInstallation.environment == environment)
        return query.order_by(DeviceInstallation.created_at.desc()).all()

    @staticmethod
    def list_active_installations_for_user(
        db: Session,
        *,
        user_id: str,
    ) -> list[DeviceInstallation]:
        """List active installations currently bound to the signed-in user."""
        return DeviceInstallationService.list_active_tokens(db, user_id)

    @staticmethod
    def _find_active_installation_by_id(
        db: Session,
        *,
        installation_id: str,
    ) -> DeviceInstallation | None:
        return (
            db.query(DeviceInstallation)
            .filter(
                DeviceInstallation.installation_id == installation_id,
                DeviceInstallation.disabled_at.is_(None),
            )
            .one_or_none()
        )

    @staticmethod
    def _find_active_installation_by_token(
        db: Session,
        *,
        token: str,
    ) -> DeviceInstallation | None:
        return (
            db.query(DeviceInstallation)
            .filter(
                DeviceInstallation.token == token,
                DeviceInstallation.disabled_at.is_(None),
            )
            .one_or_none()
        )

    @staticmethod
    def _find_bound_installation(
        db: Session,
        *,
        user_id: str,
        installation_id: str | None,
        token: str | None,
    ) -> DeviceInstallation | None:
        filters = [DeviceInstallationUser.user_id == user_id]
        installation_id_text = str(installation_id or "").strip()
        token_text = str(token or "").strip()
        if installation_id_text and token_text:
            filters.append(
                or_(
                    DeviceInstallation.installation_id == installation_id_text,
                    DeviceInstallation.token == token_text,
                )
            )
        elif installation_id_text:
            filters.append(DeviceInstallation.installation_id == installation_id_text)
        elif token_text:
            filters.append(DeviceInstallation.token == token_text)
        else:
            raise BadRequestError("installation_id or token required")

        return (
            db.query(DeviceInstallation)
            .join(
                DeviceInstallationUser,
                DeviceInstallationUser.installation_pk == DeviceInstallation.id,
            )
            .filter(
                *filters,
                DeviceInstallationUser.unbound_at.is_(None),
                DeviceInstallation.disabled_at.is_(None),
            )
            .one_or_none()
        )

    @staticmethod
    def _bind_installation_to_user(
        db: Session,
        *,
        installation_pk,
        user_id: str,
        now: datetime,
    ) -> None:
        active_bindings = (
            db.query(DeviceInstallationUser)
            .filter(
                DeviceInstallationUser.installation_pk == installation_pk,
                DeviceInstallationUser.unbound_at.is_(None),
            )
            .all()
        )

        for binding in active_bindings:
            if binding.user_id == user_id:
                binding.updated_at = now
                return
            binding.unbound_at = now
            binding.updated_at = now

        db.add(
            DeviceInstallationUser(
                installation_pk=installation_pk,
                user_id=user_id,
                bound_at=now,
                unbound_at=None,
                created_at=now,
                updated_at=now,
            )
        )

    @staticmethod
    def _disable_installation_row(
        db: Session,
        installation: DeviceInstallation,
        *,
        now: datetime,
    ) -> None:
        installation.disabled_at = now
        installation.is_foreground = False
        installation.updated_at = now
        (
            db.query(DeviceInstallationUser)
            .filter(
                DeviceInstallationUser.installation_pk == installation.id,
                DeviceInstallationUser.unbound_at.is_(None),
            )
            .update(
                {
                    DeviceInstallationUser.unbound_at: now,
                    DeviceInstallationUser.updated_at: now,
                },
                synchronize_session=False,
            )
        )
