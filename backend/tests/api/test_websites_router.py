import uuid
from datetime import UTC, datetime

from api.config import settings
from api.db.dependencies import DEFAULT_USER_ID
from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.website import Website
from api.routers.websites_helpers import website_summary
from sqlalchemy import inspect
from sqlalchemy.orm import load_only
from sqlalchemy.orm.attributes import NO_VALUE

from tests.helpers import error_message


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_websites_search_requires_query(test_client):
    response = test_client.post(
        "/api/websites/search", params={"query": ""}, headers=_auth_headers()
    )
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
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
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
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
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
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
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

    record = (
        test_db.query(IngestedFile)
        .filter(IngestedFile.id == uuid.UUID(file_id))
        .first()
    )
    assert record is not None
    assert record.source_url == "https://www.youtube.com/watch?v=pmktCumtzk4"
    assert record.source_metadata["website_id"] == str(website_id)
    assert record.source_metadata["video_id"] == "pmktCumtzk4"

    job = (
        test_db.query(FileProcessingJob)
        .filter(FileProcessingJob.file_id == record.id)
        .first()
    )
    assert job is not None


def test_archived_list_returns_field_reading_time(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=DEFAULT_USER_ID,
        url="https://example.com/metadata-reading-time",
        url_full="https://example.com/metadata-reading-time",
        domain="example.com",
        title="Metadata Reading Time",
        content="Example content",
        reading_time="104 min",
        metadata_={"pinned": False, "archived": True},
        is_archived=True,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(website)
    test_db.commit()

    response = test_client.get("/api/websites/archived", headers=_auth_headers())
    assert response.status_code == 200
    payload = response.json()
    item = next(site for site in payload["items"] if site["id"] == str(website_id))
    assert item["reading_time"] == "1 hr 44 mins"


def test_website_summary_does_not_lazy_load_deferred_content(test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=DEFAULT_USER_ID,
        url="https://example.com/deferred-content",
        url_full="https://example.com/deferred-content",
        domain="example.com",
        title="Deferred Content",
        content="---\nreading_time: '14 min'\n---\n\nBody",
        metadata_={"pinned": False, "archived": True},
        is_archived=True,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(website)
    test_db.commit()

    listed = (
        test_db.query(Website)
        .options(
            load_only(
                Website.id,
                Website.title,
                Website.url,
                Website.domain,
                Website.saved_at,
                Website.published_at,
                Website.metadata_,
                Website.is_archived,
                Website.updated_at,
                Website.last_opened_at,
            )
        )
        .filter(Website.id == website_id)
        .one()
    )

    assert inspect(listed).attrs.content.loaded_value is NO_VALUE
    assert inspect(listed).attrs.reading_time.loaded_value is NO_VALUE
    summary = website_summary(listed)
    assert summary["reading_time"] is None
    assert inspect(listed).attrs.content.loaded_value is NO_VALUE
    assert inspect(listed).attrs.reading_time.loaded_value is NO_VALUE
