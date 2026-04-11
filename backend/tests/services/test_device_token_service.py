from __future__ import annotations

from datetime import UTC, datetime

from api.models.device_installation import DeviceInstallationUser
from api.services.device_token_service import DeviceTokenService


def test_register_token_uses_token_as_installation_id_when_missing(test_db):
    record = DeviceTokenService.register_token(
        test_db,
        "user-123",
        token="device-token-123",
        platform="ios",
        environment="prod",
        capabilities={"supports_live_activities": True},
    )
    test_db.commit()

    assert record.installation_id == "device-token-123"
    assert record.token == "device-token-123"
    assert record.platform == "ios"
    assert record.environment == "prod"
    assert record.capabilities == {"supports_live_activities": True}
    assert record.disabled_at is None

    bindings = (
        test_db.query(DeviceInstallationUser)
        .filter(DeviceInstallationUser.installation_pk == record.id)
        .all()
    )
    assert len(bindings) == 1
    assert bindings[0].user_id == "user-123"
    assert bindings[0].unbound_at is None


def test_disable_token_unbinds_only_the_current_user(test_db):
    record = DeviceTokenService.register_token(
        test_db,
        "user-123",
        installation_id="install-123",
        token="device-token-123",
        platform="ios",
        environment="prod",
        capabilities={"supports_live_activities": False},
    )
    test_db.commit()

    disabled = DeviceTokenService.disable_token(
        test_db,
        "user-123",
        token="device-token-123",
        installation_id="install-123",
    )
    test_db.commit()

    assert disabled is True
    refreshed = DeviceTokenService.list_active_tokens(test_db, "user-123")
    assert refreshed == []

    bindings = (
        test_db.query(DeviceInstallationUser)
        .filter(DeviceInstallationUser.installation_pk == record.id)
        .all()
    )
    assert len(bindings) == 1
    assert bindings[0].user_id == "user-123"
    assert bindings[0].unbound_at is not None


def test_update_presence_accepts_installation_id_and_token_fallback(test_db):
    record = DeviceTokenService.register_token(
        test_db,
        "user-123",
        installation_id="install-123",
        token="device-token-123",
        platform="ios",
        environment="prod",
        capabilities={"supports_live_activities": True},
    )
    test_db.commit()

    seen_at = datetime(2026, 4, 11, 16, 0, tzinfo=UTC)
    updated = DeviceTokenService.update_presence(
        test_db,
        "user-123",
        installation_id="install-123",
        is_foreground=True,
        last_seen_at=seen_at,
    )
    test_db.commit()

    assert updated is not None
    assert updated.id == record.id
    assert updated.is_foreground is True
    assert updated.last_seen_at == seen_at

    updated_again = DeviceTokenService.update_presence(
        test_db,
        "user-123",
        token="device-token-123",
        is_foreground=False,
        last_seen_at=None,
    )
    test_db.commit()

    assert updated_again is not None
    assert updated_again.id == record.id
    assert updated_again.is_foreground is False
    assert updated_again.last_seen_at is None
