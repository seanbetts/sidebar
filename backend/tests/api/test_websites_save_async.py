"""Tests for async website save endpoint."""

import os

import pytest
from api.config import settings
from api.middleware import rate_limit as rate_limit_module


TEST_USER_ID = os.environ["TEST_USER_ID"]


@pytest.fixture(autouse=True)
def _reset_rate_limiter():
    rate_limit_module.rate_limiter.reset()
    yield
    rate_limit_module.rate_limiter.reset()


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_save_website_returns_202_with_job_id(test_client, test_db):
    """POST /websites/save should create a job and return 202."""
    response = test_client.post(
        "/api/websites/save",
        json={"url": "https://example.com"},
        headers=_auth_headers(),
    )
    assert response.status_code == 202
    data = response.json()
    assert "job_id" in data
    assert data["status"] == "queued"


def test_save_website_validates_url(test_client):
    """POST /websites/save should still validate empty URLs."""
    response = test_client.post(
        "/api/websites/save",
        json={"url": ""},
        headers=_auth_headers(),
    )
    assert response.status_code == 400


def test_save_website_missing_url(test_client):
    """POST /websites/save should reject missing url field."""
    response = test_client.post(
        "/api/websites/save",
        json={},
        headers=_auth_headers(),
    )
    assert response.status_code == 400
