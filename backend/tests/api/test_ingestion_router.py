from api.config import settings


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_ingestion_upload_and_meta(test_client):
    response = test_client.post(
        "/api/ingestion",
        headers=_auth_headers(),
        files={"file": ("sample.pdf", b"%PDF-1.4", "application/pdf")},
    )
    assert response.status_code == 200
    file_id = response.json().get("file_id")
    assert file_id

    meta = test_client.get(f"/api/ingestion/{file_id}/meta", headers=_auth_headers())
    assert meta.status_code == 200
    payload = meta.json()
    assert payload["file"]["id"] == file_id
    assert payload["job"]["status"] in {"queued", "processing", "ready", "failed", "canceled"}


def test_ingestion_pause_resume_cancel(test_client):
    response = test_client.post(
        "/api/ingestion",
        headers=_auth_headers(),
        files={"file": ("sample.pdf", b"%PDF-1.4", "application/pdf")},
    )
    file_id = response.json().get("file_id")
    assert file_id

    pause = test_client.post(f"/api/ingestion/{file_id}/pause", headers=_auth_headers())
    assert pause.status_code == 200

    resume = test_client.post(f"/api/ingestion/{file_id}/resume", headers=_auth_headers())
    assert resume.status_code == 200

    cancel = test_client.post(f"/api/ingestion/{file_id}/cancel", headers=_auth_headers())
    assert cancel.status_code == 200
