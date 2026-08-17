import pytest

from api.config import Settings


def test_worker_lifecycle_settings_default_to_safe_disabled_values(monkeypatch) -> None:
    """Lifecycle controls must remain safely disabled until explicitly enabled."""
    monkeypatch.delenv("WORKER_DEMAND_MONITOR_ENABLED", raising=False)
    monkeypatch.delenv("WEBSITE_WORKER_IDLE_EXIT_SECONDS", raising=False)
    monkeypatch.delenv("INGESTION_WORKER_IDLE_EXIT_SECONDS", raising=False)

    app_settings = Settings(auth_dev_mode=False)

    assert app_settings.worker_demand_monitor_enabled is False
    assert app_settings.worker_demand_poll_seconds == 5
    assert app_settings.website_worker_idle_exit_seconds == 0
    assert app_settings.ingestion_worker_idle_exit_seconds == 0
    assert app_settings.notification_schedule_interval_seconds == 300


def test_fly_worker_control_token_uses_secret_string() -> None:
    """The Fly worker token must not be exposed in its representation."""
    app_settings = Settings(
        auth_dev_mode=False,
        fly_worker_control_token="secret-token",
    )

    assert app_settings.fly_worker_control_token is not None
    assert app_settings.fly_worker_control_token.get_secret_value() == "secret-token"
    assert "secret-token" not in repr(app_settings.fly_worker_control_token)


@pytest.mark.parametrize("raw_token", ["", "  \t\n"])
def test_blank_fly_worker_control_token_input_normalizes_to_none(
    raw_token: str,
) -> None:
    """Blank direct token input must not become a configured secret."""
    app_settings = Settings(
        auth_dev_mode=False,
        fly_worker_control_token=raw_token,
    )

    assert app_settings.fly_worker_control_token is None


@pytest.mark.parametrize("raw_token", ["", "  \t"])
def test_blank_fly_worker_control_token_environment_normalizes_to_none(
    monkeypatch: pytest.MonkeyPatch,
    raw_token: str,
) -> None:
    """Blank environment tokens must not become configured secrets."""
    monkeypatch.setenv("FLY_WORKER_CONTROL_TOKEN", raw_token)

    app_settings = Settings(auth_dev_mode=False)

    assert app_settings.fly_worker_control_token is None


def test_get_test_user_id_prefers_runtime_env(monkeypatch):
    monkeypatch.setenv("TEST_USER_ID", "runtime-user-id")

    settings = Settings(auth_dev_mode=False)

    assert settings.get_test_user_id() == "runtime-user-id"
    assert settings.default_user_id == "runtime-user-id"


def test_settings_requires_test_user_id_in_auth_dev_mode(monkeypatch):
    monkeypatch.delenv("TEST_USER_ID", raising=False)

    with pytest.raises(ValueError, match="TEST_USER_ID must be set"):
        Settings(auth_dev_mode=True, test_user_id="")
