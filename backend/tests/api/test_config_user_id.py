import pytest

from api.config import Settings


def test_get_test_user_id_prefers_runtime_env(monkeypatch):
    monkeypatch.setenv("TEST_USER_ID", "runtime-user-id")

    settings = Settings(auth_dev_mode=False)

    assert settings.get_test_user_id() == "runtime-user-id"
    assert settings.default_user_id == "runtime-user-id"


def test_settings_requires_test_user_id_in_auth_dev_mode(monkeypatch):
    monkeypatch.delenv("TEST_USER_ID", raising=False)

    with pytest.raises(ValueError, match="TEST_USER_ID must be set"):
        Settings(auth_dev_mode=True, test_user_id="")
