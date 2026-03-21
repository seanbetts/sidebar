"""Tests for website job status endpoint."""

import os
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from api.config import settings
from api.services.website_processing_service import WebsiteProcessingService
from api.services.websites_service import WebsitesService


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
    """GET /websites/jobs/{id} returns completed status with website payload."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    website = WebsitesService.save_website(
        test_db,
        TEST_USER_ID,
        url="https://example.com",
        title="Example",
        content="Saved content",
    )
    WebsiteProcessingService.update_job(
        test_db, job.id, status="completed", website_id=website.id
    )
    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "completed"
    assert data["website"]["id"] == str(website.id)


def test_get_job_status_completed_without_website_is_not_completed(
    test_client, test_db
):
    """GET /websites/jobs/{id} fails if completion has no website payload."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    WebsiteProcessingService.update_job(test_db, job.id, status="completed")

    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "failed"
    assert (
        data["error"]["message"]
        == "Unable to save website: save completed without a website."
    )


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
    """GET /websites/jobs/{id} reports failed when the worker appears unavailable."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    job.updated_at = datetime.now(UTC) - timedelta(minutes=5)
    test_db.commit()

    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "failed"
    assert (
        data["error"]["message"]
        == "Website processing is temporarily unavailable. Please retry in a few minutes."
    )


def test_get_job_status_reports_stalled_queued_job_when_worker_is_active(
    test_client, test_db
):
    """GET /websites/jobs/{id} keeps queued jobs stalled when a worker is active."""
    stale_job = WebsiteProcessingService.create_job(
        test_db, TEST_USER_ID, "https://example.com"
    )
    stall_age = max(
        settings.website_worker_lease_seconds,
        settings.website_save_timeout_seconds,
    )
    stale_job.updated_at = datetime.now(UTC) - timedelta(seconds=stall_age + 1)

    active_job = WebsiteProcessingService.create_job(
        test_db, "other-user", "https://example.org"
    )
    active_job.status = "processing"
    active_job.worker_id = "worker-1"
    active_job.updated_at = datetime.now(UTC)
    test_db.commit()

    response = test_client.get(
        f"/api/websites/jobs/{stale_job.id}",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "stalled"
    assert data["error"]["message"] == "Website save is still waiting for a worker. Try again."


def test_get_job_status_reports_canceled_job(test_client, test_db):
    """GET /websites/jobs/{id} returns canceled as a terminal status."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    WebsiteProcessingService.cancel_job(test_db, TEST_USER_ID, job.id)

    response = test_client.get(
        f"/api/websites/jobs/{job.id}",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "canceled"
    assert "website" not in data


def test_get_job_status_not_found(test_client):
    """GET /websites/jobs/{id} returns 404 for unknown job."""
    response = test_client.get(
        f"/api/websites/jobs/{uuid4()}",
        headers=_auth_headers(),
    )
    assert response.status_code == 404


def test_cancel_job_marks_job_canceled(test_client, test_db):
    """POST /websites/jobs/{id}/cancel marks an active job as canceled."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")

    response = test_client.post(
        f"/api/websites/jobs/{job.id}/cancel",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    assert response.json()["status"] == "canceled"
    test_db.refresh(job)
    assert job.status == "canceled"
    assert job.lease_expires_at is None
    assert job.worker_id is None


def test_update_job_does_not_override_canceled_status(test_db):
    """Canceled jobs should stay canceled if the worker reports a later outcome."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    WebsiteProcessingService.cancel_job(test_db, TEST_USER_ID, job.id)

    WebsiteProcessingService.update_job(
        test_db,
        job.id,
        status="completed",
        website_id=uuid4(),
    )

    test_db.refresh(job)
    assert job.status == "canceled"


def test_status_for_client_uses_worker_lease_for_queued_jobs(monkeypatch, test_db):
    """Queued jobs should become stalled based on worker lease, not the larger save timeout."""
    monkeypatch.setattr(settings, "website_worker_lease_seconds", 60)
    monkeypatch.setattr(settings, "website_save_timeout_seconds", 300)

    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    job.updated_at = datetime.now(UTC) - timedelta(seconds=90)
    test_db.commit()

    status, error = WebsiteProcessingService.status_for_client(job)

    assert status == "stalled"
    assert error == "Website save is still waiting for a worker. Try again."


def test_update_job_clears_worker_metadata_for_failed_jobs(test_db):
    """Failed jobs should release their worker lease immediately."""
    job = WebsiteProcessingService.create_job(test_db, TEST_USER_ID, "https://example.com")
    job.status = "processing"
    job.worker_id = "worker-1"
    job.lease_expires_at = datetime.now(UTC) + timedelta(minutes=3)
    test_db.commit()

    WebsiteProcessingService.update_job(
        test_db,
        job.id,
        status="failed",
        error_message="Script execution timeout (60s)",
    )

    test_db.refresh(job)
    assert job.status == "failed"
    assert job.worker_id is None
    assert job.lease_expires_at is None
