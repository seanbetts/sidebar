from datetime import datetime, timezone
import uuid

from api.config import settings
from tests.helpers import error_message
from api.db.dependencies import DEFAULT_USER_ID
from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.website import Website


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_websites_search_requires_query(test_client):
    response = test_client.post("/api/websites/search", params={"query": ""}, headers=_auth_headers())
    assert response.status_code == 400
    assert error_message(response) == "query required"


def test_websites_save_requires_url(test_client):
    response = test_client.post("/api/websites/save", json={}, headers=_auth_headers())
    assert response.status_code == 400
    assert error_message(response) == "url required"


def test_websites_get_success(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=DEFAULT_USER_ID,
        url="https://example.com",
        url_full="https://example.com",
        domain="example.com",
        title="Example",
        content="Example content",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    test_db.add(website)
    test_db.commit()

    response = test_client.get(f"/api/websites/{website_id}", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(website_id)
    assert body["content"] == "Example content"


def test_websites_pin_rename_archive(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=DEFAULT_USER_ID,
        url="https://example.org",
        url_full="https://example.org",
        domain="example.org",
        title="Example Org",
        content="Example content",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    test_db.add(website)
    test_db.commit()

    pin = test_client.patch(
        f"/api/websites/{website_id}/pin",
        json={"pinned": True},
        headers=_auth_headers(),
    )
    assert pin.status_code == 200

    rename = test_client.patch(
        f"/api/websites/{website_id}/rename",
        json={"title": "Renamed"},
        headers=_auth_headers(),
    )
    assert rename.status_code == 200

    archive = test_client.patch(
        f"/api/websites/{website_id}/archive",
        json={"archived": True},
        headers=_auth_headers(),
    )
    assert archive.status_code == 200


def test_websites_youtube_transcript_enqueues_job(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=DEFAULT_USER_ID,
        url="https://example.com/video",
        url_full="https://example.com/video",
        domain="example.com",
        title="Video Test",
        content="[YouTube](https://www.youtube.com/watch?v=pmktCumtzk4)",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    test_db.add(website)
    test_db.commit()

    response = test_client.post(
        f"/api/websites/{website_id}/youtube-transcript",
        json={"url": "https://youtu.be/pmktCumtzk4"},
        headers=_auth_headers(),
    )
    assert response.status_code == 202
    payload = response.json()
    file_id = payload["data"]["file_id"]
    assert payload["data"]["status"] == "queued"

    record = test_db.query(IngestedFile).filter(IngestedFile.id == uuid.UUID(file_id)).first()
    assert record is not None
    assert record.source_url == "https://www.youtube.com/watch?v=pmktCumtzk4"
    assert record.source_metadata["website_id"] == str(website_id)
    assert record.source_metadata["video_id"] == "pmktCumtzk4"

    job = test_db.query(FileProcessingJob).filter(FileProcessingJob.file_id == record.id).first()
    assert job is not None
