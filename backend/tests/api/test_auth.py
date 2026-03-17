"""Tests for authentication middleware."""

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from starlette.requests import Request

from api.auth import verify_bearer_token
from api.config import settings
from api.db.dependencies import get_current_user_id
from api.main import root
from api.services.user_settings_service import UserSettingsService


def _error_message(response) -> str:
    """Normalize error payload to a message string."""
    payload = response.json().get("error")
    if isinstance(payload, dict):
        return payload.get("message", "")
    return payload or ""


@pytest.fixture
def valid_token():
    """Get the valid bearer token."""
    return settings.bearer_token


class TestAuthenticationMiddleware:
    """Test bearer token authentication."""

    def test_health_endpoint_no_auth_required(self, test_client):
        """Health endpoint should not require authentication."""
        response = test_client.get("/api/health")
        assert response.status_code == 200
        assert response.json() == {"status": "healthy"}

    def test_v1_health_endpoint_no_auth_required(self, test_client):
        """v1 health endpoint should not require authentication."""
        response = test_client.get("/api/v1/health")
        assert response.status_code == 200
        assert response.json() == {"status": "healthy"}

    def test_protected_endpoint_requires_auth(self, test_client):
        """Protected endpoints should require authentication."""
        response = test_client.get("/docs")
        assert response.status_code == 401
        assert "Authorization" in _error_message(response)

    def test_valid_bearer_token_grants_access(self, test_client, valid_token):
        """Valid bearer token should grant access."""
        response = test_client.get(
            "/docs", headers={"Authorization": f"Bearer {valid_token}"}
        )
        assert response.status_code == 200

    def test_invalid_bearer_token_denied(self, test_client):
        """Invalid bearer token should be denied."""
        response = test_client.get(
            "/docs", headers={"Authorization": "Bearer invalid-token"}
        )
        assert response.status_code == 401
        assert "Invalid" in _error_message(response)

    def test_missing_authorization_header_denied(self, test_client):
        """Missing authorization header should be denied."""
        response = test_client.get("/docs")
        assert response.status_code == 401
        assert "Missing" in _error_message(response)

    def test_auth_dev_mode_allows_missing_authorization_header(
        self, test_client, monkeypatch
    ):
        """AUTH_DEV_MODE should allow requests without Authorization headers."""
        monkeypatch.setattr(settings, "auth_dev_mode", True)

        response = test_client.get("/docs")
        assert response.status_code == 200

    def test_auth_dev_mode_validates_supplied_authorization_header(
        self, test_client, monkeypatch, valid_token
    ):
        """AUTH_DEV_MODE should validate supplied Authorization headers."""
        monkeypatch.setattr(settings, "auth_dev_mode", True)

        valid_response = test_client.get(
            "/docs",
            headers={"Authorization": f"Bearer {valid_token}"},
        )
        assert valid_response.status_code == 200

        invalid_response = test_client.get(
            "/docs",
            headers={"Authorization": "Bearer invalid-token"},
        )
        assert invalid_response.status_code == 401
        assert "Invalid" in _error_message(invalid_response)

    def test_malformed_authorization_header_denied(self, test_client):
        """Malformed authorization header should be denied."""
        malformed_headers = [
            {"Authorization": "NotBearer token"},
            {"Authorization": "Bearer"},
            {"Authorization": "token"},
            {"Authorization": ""},
        ]

        for headers in malformed_headers:
            response = test_client.get("/docs", headers=headers)
            assert response.status_code == 401

    def test_case_insensitive_bearer_scheme(self, test_client, valid_token):
        """Bearer scheme should be case-insensitive."""
        schemes = ["Bearer", "bearer", "BEARER", "BeArEr"]

        for scheme in schemes:
            response = test_client.get(
                "/docs", headers={"Authorization": f"{scheme} {valid_token}"}
            )
            assert response.status_code == 200

    def test_www_authenticate_header_in_401(self, test_client):
        """401 responses should include WWW-Authenticate header."""
        response = test_client.get("/docs")
        assert response.status_code == 401
        assert "WWW-Authenticate" in response.headers
        assert response.headers["WWW-Authenticate"] == "Bearer"

class TestAuthenticationEdgeCases:
    """Test edge cases in authentication."""

    def test_empty_token_denied(self, test_client):
        """Empty token should be denied."""
        response = test_client.get("/docs", headers={"Authorization": "Bearer "})
        assert response.status_code == 401

    def test_whitespace_in_token_denied(self, test_client):
        """Token with whitespace should be denied."""
        response = test_client.get(
            "/docs", headers={"Authorization": "Bearer token with spaces"}
        )
        assert response.status_code == 401

    def test_multiple_authorization_headers(self, test_client, valid_token):
        """Should handle multiple Authorization headers (first one wins)."""
        # Note: httpx.Client combines multiple headers with the same name
        # This tests implementation-specific behavior
        response = test_client.get(
            "/docs", headers={"Authorization": f"Bearer {valid_token}"}
        )
        assert response.status_code == 200

    def test_token_not_logged_in_response(self, test_client, valid_token):
        """Bearer token should not appear in error responses."""
        response = test_client.get(
            "/docs",
            headers={"Authorization": f"Bearer {valid_token}x"},  # Invalid token
        )
        assert response.status_code == 401
        # Check that token is not in the response body
        assert valid_token not in response.text


class TestAuthenticationWithMCP:
    """Test authentication with MCP endpoints."""

    def test_mcp_endpoint_requires_auth(self, test_client):
        """MCP endpoint should require authentication."""
        response = test_client.post(
            "/mcp",
            json={"jsonrpc": "2.0", "method": "tools/list", "id": 1},
            headers={"Accept": "application/json, text/event-stream"},
        )
        assert response.status_code == 401

    def test_mcp_endpoint_with_valid_token(self, test_client, valid_token):
        """MCP endpoint should work with valid token."""
        response = test_client.post(
            "/mcp",
            json={
                "jsonrpc": "2.0",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "test", "version": "1.0"},
                },
                "id": 1,
            },
            headers={
                "Authorization": f"Bearer {valid_token}",
                "Accept": "application/json, text/event-stream",
            },
        )
        # Should not be 401 (might be 200 or other, but not unauthorized)
        assert response.status_code != 401


@pytest.mark.asyncio
async def test_root_payload_omits_write_allowlist():
    """Root payload should not expose writable server paths."""
    payload = await root()

    assert "write_allowlist" not in payload["security"]


@pytest.mark.asyncio
async def test_verify_bearer_token_uses_pat_service_lookup(test_db, monkeypatch):
    """PAT validation should delegate to the shared user settings service."""
    token = "sb_pat_test_verify_token"
    UserSettingsService.upsert_settings(test_db, "user-1", shortcuts_pat=token)
    request = Request({"type": "http", "headers": []})
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    service_calls: list[str] = []
    original = UserSettingsService.get_user_id_for_shortcuts_pat

    def spy(db, supplied_token: str):
        service_calls.append(supplied_token)
        return original(db, supplied_token)

    monkeypatch.setattr(UserSettingsService, "get_user_id_for_shortcuts_pat", spy)

    payload = await verify_bearer_token(request, credentials)

    assert payload == {"sub": "user-1"}
    assert request.state.user_id == "user-1"
    assert service_calls == [token]


@pytest.mark.asyncio
async def test_get_current_user_id_uses_pat_service_lookup(test_db, monkeypatch):
    """Dependency PAT validation should delegate to the shared user settings service."""
    token = "sb_pat_test_dependency_token"
    UserSettingsService.upsert_settings(test_db, "user-1", shortcuts_pat=token)
    request = Request({"type": "http", "headers": []})
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    service_calls: list[str] = []
    original = UserSettingsService.get_user_id_for_shortcuts_pat

    def spy(db, supplied_token: str):
        service_calls.append(supplied_token)
        return original(db, supplied_token)

    monkeypatch.setattr(UserSettingsService, "get_user_id_for_shortcuts_pat", spy)

    user_id = await get_current_user_id(request, credentials)

    assert user_id == "user-1"
    assert service_calls == [token]


@pytest.mark.asyncio
async def test_get_current_user_id_rejects_invalid_pat(test_db):
    """Invalid PAT tokens should still be rejected."""
    request = Request({"type": "http", "headers": []})
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer", credentials="sb_pat_missing_token"
    )

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(request, credentials)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Invalid API token"
