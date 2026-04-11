import pytest

from api.services.device_installation_service import DeviceInstallationService


@pytest.fixture
def db_session(test_db):
    return test_db


def test_register_installation_allows_one_user_to_bind_multiple_devices(db_session):
    first = DeviceInstallationService.register_installation(
        db_session,
        "user-1",
        installation_id="install-1",
        token="token-1",
        platform="ios",
        environment="prod",
        capabilities={"supports_live_activities": True},
    )
    second = DeviceInstallationService.register_installation(
        db_session,
        "user-1",
        installation_id="install-2",
        token="token-2",
        platform="ios",
        environment="prod",
        capabilities={"supports_live_activities": False},
    )
    db_session.commit()

    active_tokens = DeviceInstallationService.list_active_tokens(
        db_session,
        "user-1",
        environment="prod",
    )

    assert {installation.id for installation in active_tokens} == {
        first.id,
        second.id,
    }
    assert {installation.token for installation in active_tokens} == {
        "token-1",
        "token-2",
    }


def test_register_installation_rebinds_shared_device_to_new_user(db_session):
    DeviceInstallationService.register_installation(
        db_session,
        "user-1",
        installation_id="install-1",
        token="token-1",
        platform="ios",
        environment="prod",
    )
    db_session.commit()

    DeviceInstallationService.register_installation(
        db_session,
        "user-2",
        installation_id="install-1",
        token="token-1",
        platform="ios",
        environment="prod",
    )
    db_session.commit()

    user_one_tokens = DeviceInstallationService.list_active_tokens(
        db_session,
        "user-1",
        environment="prod",
    )
    user_two_tokens = DeviceInstallationService.list_active_tokens(
        db_session,
        "user-2",
        environment="prod",
    )
    bindings = DeviceInstallationService.list_bindings(
        db_session,
        installation_id="install-1",
    )

    assert user_one_tokens == []
    assert [installation.token for installation in user_two_tokens] == ["token-1"]
    assert len(bindings) == 2
    assert bindings[0].user_id == "user-1"
    assert bindings[0].unbound_at is not None
    assert bindings[1].user_id == "user-2"
    assert bindings[1].unbound_at is None


def test_disable_installation_unbinds_user_without_destroying_installation(db_session):
    DeviceInstallationService.register_installation(
        db_session,
        "user-1",
        installation_id="install-1",
        token="token-1",
        platform="ios",
        environment="prod",
    )
    db_session.commit()

    disabled = DeviceInstallationService.disable_installation(
        db_session,
        "user-1",
        installation_id="install-1",
    )
    db_session.commit()

    remaining_tokens = DeviceInstallationService.list_active_tokens(
        db_session,
        "user-1",
        environment="prod",
    )
    installation = DeviceInstallationService.get_installation(
        db_session,
        installation_id="install-1",
    )
    bindings = DeviceInstallationService.list_bindings(
        db_session,
        installation_id="install-1",
    )

    assert disabled is True
    assert remaining_tokens == []
    assert installation is not None
    assert installation.disabled_at is None
    assert len(bindings) == 1
    assert bindings[0].user_id == "user-1"
    assert bindings[0].unbound_at is not None
