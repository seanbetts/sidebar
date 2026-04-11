"""Compatibility wrapper around the installation-backed push service."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy.orm import Session

from api.services.device_installation_service import DeviceInstallationService


class DeviceTokenService:
    """Compatibility facade for older call sites during the migration."""

    normalize_environment = staticmethod(
        DeviceInstallationService.normalize_environment
    )
    normalize_capabilities = staticmethod(
        DeviceInstallationService.normalize_capabilities
    )
    list_active_tokens = staticmethod(DeviceInstallationService.list_active_tokens)
    disable_tokens_by_value = staticmethod(
        DeviceInstallationService.disable_tokens_by_value
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
        installation_id: str | None = None,
    ):
        """Register or rebind one installation for the current user."""
        resolved_installation_id = str(installation_id or token or "").strip()
        return DeviceInstallationService.register_installation(
            db,
            user_id,
            installation_id=resolved_installation_id,
            token=token,
            platform=platform,
            environment=environment,
            capabilities=capabilities,
        )

    @staticmethod
    def update_presence(
        db: Session,
        user_id: str,
        *,
        token: str | None = None,
        installation_id: str | None = None,
        is_foreground: bool,
        last_seen_at: datetime | None,
    ):
        """Update install presence for the current user."""
        return DeviceInstallationService.update_presence(
            db,
            user_id,
            installation_id=installation_id,
            token=token,
            is_foreground=is_foreground,
            last_seen_at=last_seen_at,
        )

    @staticmethod
    def disable_token(
        db: Session,
        user_id: str,
        token: str,
        *,
        installation_id: str | None = None,
    ) -> bool:
        """Unbind the current user from one installation."""
        return DeviceInstallationService.disable_installation(
            db,
            user_id,
            installation_id=installation_id,
            token=token,
        )
