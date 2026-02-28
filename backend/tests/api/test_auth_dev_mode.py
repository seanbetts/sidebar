"""Tests for AUTH_DEV_MODE behavior with and without supplied tokens."""

import pytest
from fastapi import Request
from fastapi.security import HTTPAuthorizationCredentials

from api import auth as auth_module
from api.auth import verify_bearer_token
from api.config import settings
from api.db.dependencies import get_current_user_id


def _make_request() -> Request:
    return Request({"type": "http", "headers": []})


@pytest.mark.asyncio
async def test_verify_bearer_token_uses_test_user_without_header(monkeypatch):
    monkeypatch.setattr(settings, "auth_dev_mode", True)

    request = _make_request()
    payload = await verify_bearer_token(request, credentials=None)

    assert payload["sub"] == settings.require_test_user_id()
    assert request.state.user_id == settings.require_test_user_id()


@pytest.mark.asyncio
async def test_verify_bearer_token_uses_supplied_header_when_present(monkeypatch):
    monkeypatch.setattr(settings, "auth_dev_mode", True)

    async def fake_validate_token(self, token: str) -> dict:
        assert token == "jwt-token"
        return {"sub": "jwt-user-id"}

    monkeypatch.setattr(
        auth_module.SupabaseJWTValidator,
        "validate_token",
        fake_validate_token,
    )

    request = _make_request()
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="jwt-token",
    )
    payload = await verify_bearer_token(request, credentials=credentials)

    assert payload["sub"] == "jwt-user-id"
    assert request.state.user_id == "jwt-user-id"


@pytest.mark.asyncio
async def test_get_current_user_id_uses_test_user_without_header(monkeypatch):
    monkeypatch.setattr(settings, "auth_dev_mode", True)

    request = _make_request()
    user_id = await get_current_user_id(request, credentials=None)

    assert user_id == settings.require_test_user_id()


@pytest.mark.asyncio
async def test_get_current_user_id_prefers_request_state_user_when_present(monkeypatch):
    monkeypatch.setattr(settings, "auth_dev_mode", True)

    request = _make_request()
    request.state.user_id = "jwt-user-id"
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="jwt-token",
    )
    user_id = await get_current_user_id(request, credentials=credentials)

    assert user_id == "jwt-user-id"


@pytest.mark.asyncio
async def test_get_current_user_id_persists_active_user_hint_file(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "auth_dev_mode", True)
    monkeypatch.setattr(settings, "app_env", "local")
    active_user_file = tmp_path / "active-user-id.txt"
    monkeypatch.setenv("INGESTION_ACTIVE_USER_FILE", str(active_user_file))

    request = _make_request()
    request.state.user_id = "jwt-user-id"
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="jwt-token",
    )
    user_id = await get_current_user_id(request, credentials=credentials)

    assert user_id == "jwt-user-id"
    assert active_user_file.read_text(encoding="utf-8") == "jwt-user-id"
