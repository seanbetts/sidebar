"""Tests for website job status endpoint."""

import os
from uuid import uuid4

from api.config import settings
from api.services.website_processing_service import WebsiteProcessingService


TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_get_job_status_queued(test_client, test_db):
    """GET /websites/jobs/{id} returns queued status."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    data = response.json()
    assert data["job_id"] == str(job.id)
    assert data["status"] == "queued"
    assert "website" not in data


def test_get_job_status_completed(test_client, test_db):
    """GET /websites/jobs/{id} returns completed status."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    WebsiteProcessingService.update_job(
        test_db, job.id, status="completed", website_id=None
    )
    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "completed"


def test_get_job_status_failed(test_client, test_db):
    """GET /websites/jobs/{id} returns error details when failed."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    WebsiteProcessingService.update_job(
        test_db,
        job.id,
        status="failed",
        error_message="Script execution timeout (120s)",
    )
    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "failed"
    assert "error" in data
    assert data["error"]["message"] == "Script execution timeout (120s)"


def test_get_job_status_not_found(test_client):
    """GET /websites/jobs/{id} returns 404 for unknown job."""
    response = test_client.get(
        f"/api/websites/jobs/{uuid4()}",
        headers=_auth_headers(),
    )
    assert response.status_code == 404
