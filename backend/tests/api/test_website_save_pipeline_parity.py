import os
import uuid
from datetime import UTC, datetime

import pytest

from api.config import settings
from api.models.website import Website
from api.services.agent.tools.mapper import ToolMapper

TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def _persist_website(
    test_db,
    *,
    website_id: uuid.UUID,
    url: str,
    title: str,
    content: str,
) -> Website:
    website = Website(
        id=website_id,
        user_id=TEST_USER_ID,
        url=url,
        url_full=f"{url}?ref=canonical",
        domain="example.com",
        title=title,
        content=content,
        source="web",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(website)
    test_db.commit()
    return website


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


def test_save_website_endpoint_returns_202_with_job_id(test_client, test_db):
    """Save endpoint creates a job and returns 202 with job_id."""
    url = "https://example.com/article"

    save_response = test_client.post(
        "/api/websites/save",
        json={"url": url},
        headers=_auth_headers(),
    )
    assert save_response.status_code == 202
    body = save_response.json()
    assert "job_id" in body
    assert body["status"] == "queued"


def test_save_website_endpoint_creates_job_for_duplicate_url(
    test_client, test_db,
):
    """Saving the same URL twice creates two separate jobs."""
    url = "https://example.com/article"

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

    assert first.status_code == 202
    assert second.status_code == 202
    assert first.json()["job_id"] != second.json()["job_id"]


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
