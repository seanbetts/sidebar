"""Tests for website job status endpoint."""

import os
from datetime import UTC, datetime, timedelta
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


def test_get_job_status_reports_stalled_processing_job(test_client, test_db):
    """GET /websites/jobs/{id} reports stalled when the lease has expired."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    job.status = "processing"
    job.worker_id = "worker-1"
    job.lease_expires_at = datetime.now(UTC) - timedelta(seconds=5)
    job.updated_at = datetime.now(UTC)
    test_db.commit()

    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "stalled"
    assert data["error"]["message"] == "Website save stalled before completion. Try again."


def test_get_job_status_reports_stalled_queued_job(test_client, test_db):
    """GET /websites/jobs/{id} reports stalled when no worker has picked it up in time."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    stall_age = max(
        settings.website_worker_lease_seconds,
        settings.website_save_timeout_seconds,
    )
    job.updated_at = datetime.now(UTC) - timedelta(seconds=stall_age + 1)
    test_db.commit()

    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "stalled"
    assert data["error"]["message"] == "Website save is still waiting for a worker. Try again."


def test_get_job_status_not_found(test_client):
    """GET /websites/jobs/{id} returns 404 for unknown job."""
    response = test_client.get(
        f"/api/websites/jobs/{uuid4()}",
        headers=_auth_headers(),
    )
    assert response.status_code == 404
