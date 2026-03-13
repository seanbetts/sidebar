import os
import uuid
from datetime import UTC, datetime

from api.config import settings
from api.exceptions import WebsiteNotFoundError
from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.website import Website
from api.schemas.filters import WebsiteFilters
from api.routers.websites_helpers import website_summary
from api.services.websites_service import WebsitesService
from sqlalchemy import inspect
from sqlalchemy.orm import load_only
from sqlalchemy.orm.attributes import NO_VALUE

from tests.helpers import error_message

TEST_USER_ID = os.environ["TEST_USER_ID"]


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


def test_websites_save_reports_local_and_jina_payment_error(test_client, monkeypatch):
    async def fake_execute(_skill, _script, _args, user_id=None):
        return {
            "success": False,
            "error": {
                "type": "FetchError",
                "message": (
                    "Local parse failed (No readable content extracted); "
                    "Jina fallback failed: Failed to fetch content from Jina.ai: "
                    "402 Client Error: Payment Required for url: "
                    "https://r.jina.ai/https://example.com"
                ),
            },
        }

    monkeypatch.setattr(test_client.app.state.executor, "execute", fake_execute)
    response = test_client.post(
        "/api/websites/save",
        json={"url": "https://example.com"},
        headers=_auth_headers(),
    )

    assert response.status_code == 400
    assert (
        error_message(response)
        == "Unable to save website: local parser found no readable content and "
        "Jina fallback returned 402 Payment Required."
    )
    assert (
        response.json()["error"]["details"]["code"]
        == "WEB_SAVE_LOCAL_PARSE_AND_JINA_PAYMENT_REQUIRED"
    )


def test_websites_save_reports_no_readable_content(test_client, monkeypatch):
    captured: dict[str, str | None] = {}

    async def fake_execute(_skill, _script, _args, user_id=None):
        captured["user_id"] = user_id
        return {
            "success": False,
            "error": "No readable content extracted",
        }

    monkeypatch.setattr(test_client.app.state.executor, "execute", fake_execute)
    response = test_client.post(
        "/api/websites/save",
        json={"url": "https://example.com"},
        headers=_auth_headers(),
    )

    assert response.status_code == 400
    assert (
        error_message(response)
        == "Unable to save website: local parser found no readable content."
    )
    assert (
        response.json()["error"]["details"]["code"] == "WEB_SAVE_NO_READABLE_CONTENT"
    )
    assert captured["user_id"] == TEST_USER_ID


def test_websites_save_returns_canonical_detail(test_client, test_db, monkeypatch):
    url = "https://example.com/canonical"
    website_id = uuid.uuid4()
    saved_at = datetime.now(UTC)
    website = Website(
        id=website_id,
        user_id=TEST_USER_ID,
        url=url,
        url_full=url,
        domain="example.com",
        title="Example title",
        content="Example content",
        source=None,
        saved_at=saved_at,
        published_at=saved_at,
        reading_time=None,
        metadata_={
            "pinned": False,
            "archived": False,
            "favicon_url": "https://example.com/favicon.ico",
            "favicon_r2_key": "r2-key",
            "youtube_transcripts": {"video": "transcript"},
        },
        is_archived=False,
        created_at=saved_at,
        updated_at=saved_at,
        last_opened_at=saved_at,
        deleted_at=None,
    )
    test_db.add(website)
    test_db.commit()

    async def fake_execute(*args, **kwargs):
        return {"success": True, "data": {"id": str(website_id)}}

    monkeypatch.setattr(
        test_client.app.state.executor, "execute", fake_execute
    )

    response = test_client.post(
        "/api/websites/save",
        json={"url": url},
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    website_payload = body["website"]
    assert website_payload["id"] == str(website_id)
    assert website_payload["title"] == "Example title"
    assert website_payload["url"] == url
    assert website_payload["content"] == "Example content"
    assert website_payload["favicon_url"] == "https://example.com/favicon.ico"
    assert website_payload["favicon_r2_key"] == "r2-key"
    assert website_payload["youtube_transcripts"] == {"video": "transcript"}
    assert isinstance(website_payload["published_at"], str)


def test_websites_save_rejects_explicit_port_urls(test_client, monkeypatch):
    async def fake_execute(*args, **kwargs):
        return {"success": True, "data": {"id": str(uuid.uuid4())}}

    monkeypatch.setattr(
        test_client.app.state.executor, "execute", fake_execute
    )

    response = test_client.post(
        "/api/websites/save",
        json={"url": "https://example.com:8443/article"},
        headers=_auth_headers(),
    )

    assert response.status_code == 400
    payload = response.json()["error"]
    assert payload["code"] == "BAD_REQUEST"
    assert payload["message"] == "Invalid URL"
    assert payload["details"]["reason"] == "invalid_url"


def test_quick_save_routes_are_removed(test_client):
    create_response = test_client.post(
        "/api/websites/quick-save",
        json={"url": "https://example.com"},
        headers=_auth_headers(),
    )
    assert create_response.status_code == 404

    status_response = test_client.get(
        f"/api/websites/quick-save/{uuid.uuid4()}",
        headers=_auth_headers(),
    )
    assert status_response.status_code == 404


def test_websites_get_success(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=TEST_USER_ID,
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


def test_websites_download_handles_unicode_filename(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=TEST_USER_ID,
        url="https://example.com/openclaw",
        url_full="https://example.com/openclaw",
        domain="example.com",
        title="OpenClaw🦞",
        content="# OpenClaw",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(website)
    test_db.commit()

    response = test_client.get(
        f"/api/websites/{website_id}/download",
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    assert response.text == "# OpenClaw"
    header = response.headers["content-disposition"]
    assert 'filename="OpenClaw.md"' in header
    assert "filename*=UTF-8''OpenClaw%F0%9F%A6%9E.md" in header
    assert "🦞" not in header


def test_websites_pin_rename_archive(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=TEST_USER_ID,
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
    pin_body = pin.json()
    assert pin_body["pinned"] is True
    assert pin_body["pinned_order"] == 0

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
    archive_body = archive.json()
    assert archive_body["archived"] is True
    assert archive_body["pinned"] is False
    assert archive_body["pinned_order"] is None


def test_websites_delete_clears_pinned_state(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=TEST_USER_ID,
        url="https://example.org/delete",
        url_full="https://example.org/delete",
        domain="example.org",
        title="Delete Me",
        content="Example content",
        metadata_={"pinned": True, "archived": False, "pinned_order": 3},
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(website)
    test_db.commit()

    response = test_client.delete(
        f"/api/websites/{website_id}",
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["pinned"] is False
    assert body["pinned_order"] is None
    assert body["deleted_at"] is not None


def test_websites_youtube_transcript_enqueues_job(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=TEST_USER_ID,
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
        user_id=TEST_USER_ID,
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
        user_id=TEST_USER_ID,
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
    test_db.expunge_all()

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


def test_list_websites_preloads_deleted_at_for_summary(test_db):
    active_website = Website(
        id=uuid.uuid4(),
        user_id=TEST_USER_ID,
        url="https://example.com/active",
        url_full="https://example.com/active",
        domain="example.com",
        title="Active",
        content="Active content",
        metadata_={"pinned": False, "archived": False},
        is_archived=False,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    archived_website = Website(
        id=uuid.uuid4(),
        user_id=TEST_USER_ID,
        url="https://example.com/archived",
        url_full="https://example.com/archived",
        domain="example.com",
        title="Archived",
        content="Archived content",
        metadata_={"pinned": False, "archived": True},
        is_archived=True,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add_all([active_website, archived_website])
    test_db.commit()
    test_db.expunge_all()

    for filters in (WebsiteFilters(archived=False), WebsiteFilters(archived=True)):
        listed = WebsitesService.list_websites(test_db, TEST_USER_ID, filters)
        assert listed
        site = listed[0]

        assert inspect(site).attrs.deleted_at.loaded_value is not NO_VALUE

        summary = website_summary(site)

        assert summary["deleted_at"] is None
        assert inspect(site).attrs.deleted_at.loaded_value is None
