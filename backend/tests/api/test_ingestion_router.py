import os
import uuid

from api.config import settings
from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.website import Website


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


def test_ingestion_meta_syncs_failed_transcript_status(test_client, test_db):
    user_id = os.getenv("TEST_USER_ID", "user-1")
    video_id = "abc123xyz"
    youtube_url = f"https://www.youtube.com/watch?v={video_id}"
    file_id = uuid.uuid4()

    website = Website(
        user_id=user_id,
        url=youtube_url,
        url_full=youtube_url,
        domain="www.youtube.com",
        title="Test Video",
        content=f"[YouTube]({youtube_url})",
        source=youtube_url,
        metadata_={
            "youtube_transcripts": {
                video_id: {"status": "queued", "file_id": str(file_id)}
            }
        },
    )
    test_db.add(website)
    test_db.commit()
    test_db.refresh(website)

    record = IngestedFile(
        id=file_id,
        user_id=user_id,
        filename_original="YouTube transcript",
        path="YouTube transcript",
        mime_original="video/youtube",
        size_bytes=0,
        source_url=youtube_url,
        source_metadata={
            "provider": "youtube",
            "video_id": video_id,
            "website_id": str(website.id),
            "youtube_url": youtube_url,
            "website_transcript": True,
        },
    )
    job = FileProcessingJob(
        file_id=file_id,
        status="failed",
        stage="failed",
        error_code="VIDEO_TRANSCRIPTION_FAILED",
        error_message="Download failed",
    )
    test_db.add(record)
    test_db.flush()
    test_db.add(job)
    test_db.commit()

    response = test_client.get(f"/api/ingestion/{file_id}/meta", headers=_auth_headers())
    assert response.status_code == 200

    test_db.refresh(website)
    transcripts = website.metadata_.get("youtube_transcripts", {})
    assert transcripts[video_id]["status"] == "failed"
    assert transcripts[video_id]["file_id"] == str(file_id)
    assert transcripts[video_id]["error"] == "Download failed"
