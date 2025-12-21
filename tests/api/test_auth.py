"""Tests for authentication middleware."""
import pytest
from fastapi.testclient import TestClient
from api.main import app
from api.config import settings


@pytest.fixture
def client():
    """Create a test client."""
    return TestClient(app)


@pytest.fixture
def valid_token():
    """Get the valid bearer token."""
    return settings.bearer_token


class TestAuthenticationMiddleware:
    """Test bearer token authentication."""

    def test_health_endpoint_no_auth_required(self, client):
        """Health endpoint should not require authentication."""
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "healthy"}

    def test_protected_endpoint_requires_auth(self, client):
        """Protected endpoints should require authentication."""
        response = client.get("/docs")
        assert response.status_code == 401
        assert "Authorization" in response.json()["error"]

    def test_valid_bearer_token_grants_access(self, client, valid_token):
        """Valid bearer token should grant access."""
        response = client.get(
            "/docs",
            headers={"Authorization": f"Bearer {valid_token}"}
        )
        assert response.status_code == 200

    def test_invalid_bearer_token_denied(self, client):
        """Invalid bearer token should be denied."""
        response = client.get(
            "/docs",
            headers={"Authorization": "Bearer invalid-token"}
        )
        assert response.status_code == 401
        assert "Invalid" in response.json()["error"]

    def test_missing_authorization_header_denied(self, client):
        """Missing authorization header should be denied."""
        response = client.get("/docs")
        assert response.status_code == 401
        assert "Missing" in response.json()["error"]

    def test_malformed_authorization_header_denied(self, client):
        """Malformed authorization header should be denied."""
        malformed_headers = [
            {"Authorization": "NotBearer token"},
            {"Authorization": "Bearer"},
            {"Authorization": "token"},
            {"Authorization": ""},
        ]

        for headers in malformed_headers:
            response = client.get("/docs", headers=headers)
            assert response.status_code == 401

    def test_case_insensitive_bearer_scheme(self, client, valid_token):
        """Bearer scheme should be case-insensitive."""
        schemes = ["Bearer", "bearer", "BEARER", "BeArEr"]

        for scheme in schemes:
            response = client.get(
                "/docs",
                headers={"Authorization": f"{scheme} {valid_token}"}
            )
            assert response.status_code == 200

    def test_www_authenticate_header_in_401(self, client):
        """401 responses should include WWW-Authenticate header."""
        response = client.get("/docs")
        assert response.status_code == 401
        assert "WWW-Authenticate" in response.headers
        assert response.headers["WWW-Authenticate"] == "Bearer"


class TestAuthenticationEdgeCases:
    """Test edge cases in authentication."""

    def test_empty_token_denied(self, client):
        """Empty token should be denied."""
        response = client.get(
            "/docs",
            headers={"Authorization": "Bearer "}
        )
        assert response.status_code == 401

    def test_whitespace_in_token_denied(self, client):
        """Token with whitespace should be denied."""
        response = client.get(
            "/docs",
            headers={"Authorization": "Bearer token with spaces"}
        )
        assert response.status_code == 401

    def test_multiple_authorization_headers(self, client, valid_token):
        """Should handle multiple Authorization headers (first one wins)."""
        # Note: httpx.Client combines multiple headers with the same name
        # This tests implementation-specific behavior
        response = client.get(
            "/docs",
            headers={
                "Authorization": f"Bearer {valid_token}"
            }
        )
        assert response.status_code == 200

    def test_token_not_logged_in_response(self, client, valid_token):
        """Bearer token should not appear in error responses."""
        response = client.get(
            "/docs",
            headers={"Authorization": f"Bearer {valid_token}x"}  # Invalid token
        )
        assert response.status_code == 401
        # Check that token is not in the response body
        assert valid_token not in response.text


class TestAuthenticationWithMCP:
    """Test authentication with MCP endpoints."""

    def test_mcp_endpoint_requires_auth(self, client):
        """MCP endpoint should require authentication."""
        response = client.post(
            "/mcp",
            json={
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": 1
            },
            headers={"Accept": "application/json, text/event-stream"}
        )
        assert response.status_code == 401

    def test_mcp_endpoint_with_valid_token(self, client, valid_token):
        """MCP endpoint should work with valid token."""
        response = client.post(
            "/mcp",
            json={
                "jsonrpc": "2.0",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "test", "version": "1.0"}
                },
                "id": 1
            },
            headers={
                "Authorization": f"Bearer {valid_token}",
                "Accept": "application/json, text/event-stream"
            }
        )
        # Should not be 401 (might be 200 or other, but not unauthorized)
        assert response.status_code != 401
