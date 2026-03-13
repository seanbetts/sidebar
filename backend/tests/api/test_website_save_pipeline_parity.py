import os
import uuid
from datetime import UTC, datetime

import pytest

from api.config import settings
from api.exceptions import WebsiteNotFoundError
from api.models.website import Website
from api.services.agent.tools.mapper import ToolMapper
from api.services.websites_service import WebsitesService

TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_legacy_quick_save_routes_are_removed(test_client):
    create_response = test_client.post(
        "/api/websites/quick-save",
        json={"url": "https://example.com/article"},
        headers=_auth_headers(),
    )
    assert create_response.status_code == 404

    status_response = test_client.get(
        f"/api/websites/quick-save/{uuid.uuid4()}",
        headers=_auth_headers(),
    )
    assert status_response.status_code == 404


def test_save_website_endpoint_uses_canonical_script_contract(test_client, monkeypatch):
    url = "https://example.com/article"
    website_id = uuid.uuid4()
    expected_data = {
        "id": str(website_id),
        "title": "Example",
        "url": url,
        "domain": "example.com",
    }
    calls: list[dict[str, object]] = []

    async def fake_execute(skill, script, args, user_id=None, **kwargs):
        calls.append(
            {
                "skill": skill,
                "script": script,
                "args": list(args),
                "user_id": user_id,
            }
        )
        return {"success": True, "data": expected_data}

    monkeypatch.setattr(test_client.app.state.executor, "execute", fake_execute)

    save_response = test_client.post(
        "/api/websites/save",
        json={"url": url},
        headers=_auth_headers(),
    )
    assert save_response.status_code == 200
    assert save_response.json().get("data") == expected_data

    assert len(calls) == 1
    assert calls[0]["skill"] == "web-save"
    assert calls[0]["script"] == "save_url.py"
    assert calls[0]["args"] == [url, "--database", "--user-id", TEST_USER_ID]
    assert calls[0]["user_id"] == TEST_USER_ID


def test_save_website_endpoint_returns_existing_detail_for_duplicate_url(
    test_client, test_db, monkeypatch
):
    url = "https://example.com/article"
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
        source="test",
        saved_at=saved_at,
        published_at=saved_at,
        reading_time=None,
        metadata_={
            "pinned": True,
            "favicon_url": "https://example.com/favicon.ico",
            "favicon_r2_key": "r2-key",
            "youtube_transcripts": {},
        },
        is_archived=False,
        created_at=saved_at,
        updated_at=saved_at,
        last_opened_at=saved_at,
        deleted_at=None,
    )
    test_db.add(website)
    test_db.commit()

    responses = [
        {"success": True, "data": {"id": str(website_id)}},
        {"success": True, "data": {"id": str(website_id)}},
    ]
    call_state = {"index": 0}

    async def fake_execute(*args, **kwargs):
        idx = min(call_state["index"], len(responses) - 1)
        call_state["index"] += 1
        return responses[idx]

    monkeypatch.setattr(test_client.app.state.executor, "execute", fake_execute)

    first = test_client.post(
        "/api/websites/save",
        json={"url": url},
        headers=_auth_headers(),
    )
    second = test_client.post(
        "/api/websites/save",
        json={"url": url},
        headers=_auth_headers(),
    )

    assert first.status_code == 200
    assert second.status_code == 200

    first_payload = first.json()["website"]
    second_payload = second.json()["website"]
    assert first_payload == second_payload
    assert first_payload["id"] == str(website_id)


def test_websites_save_executor_success_but_unreadable_record_fails(
    test_client, monkeypatch
):
    website_id = uuid.uuid4()

    async def fake_execute(*args, **kwargs):
        return {"success": True, "data": {"id": str(website_id)}}

    def fake_get_website(db, user_id, website_id_value, **kwargs):
        raise WebsiteNotFoundError(str(website_id_value))

    monkeypatch.setattr(test_client.app.state.executor, "execute", fake_execute)
    monkeypatch.setattr(WebsitesService, "get_website", fake_get_website)

    response = test_client.post(
        "/api/websites/save",
        json={"url": "https://example.com/article"},
        headers=_auth_headers(),
    )

    assert response.status_code == 400
    payload = response.json()["error"]
    assert payload["code"] == "BAD_REQUEST"
    assert payload["message"] == "Failed to save website"


@pytest.mark.asyncio
async def test_ai_save_website_tool_uses_same_script_contract(monkeypatch):
    mapper = ToolMapper()
    url = "https://example.com/article"
    expected_data = {
        "id": str(uuid.uuid4()),
        "title": "Example",
        "url": url,
        "domain": "example.com",
    }
    calls: list[dict[str, object]] = []

    async def fake_execute(skill, script, args, **kwargs):
        calls.append({"skill": skill, "script": script, "args": list(args)})
        return {"success": True, "data": expected_data}

    monkeypatch.setattr(mapper.executor, "execute", fake_execute)

    result = await mapper.execute_tool(
        "Save Website",
        {"url": url},
        context={"user_id": TEST_USER_ID},
    )

    assert result["success"] is True
    assert result["data"] == expected_data
    assert len(calls) == 1
    assert calls[0]["skill"] == "web-save"
    assert calls[0]["script"] == "save_url.py"
    assert calls[0]["args"] == [url, "--database", "--user-id", TEST_USER_ID]
