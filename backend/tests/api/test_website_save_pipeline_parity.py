import os
import uuid

import pytest

from api.config import settings
from api.services.agent.tools.mapper import ToolMapper

TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_save_and_quick_save_share_same_execution_pipeline(test_client, monkeypatch):
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

    quick_save_response = test_client.post(
        "/api/websites/quick-save",
        json={"url": url},
        headers=_auth_headers(),
    )
    assert quick_save_response.status_code == 202
    quick_job_id = quick_save_response.json()["data"]["job_id"]

    quick_job_response = test_client.get(
        f"/api/websites/quick-save/{quick_job_id}",
        headers=_auth_headers(),
    )
    assert quick_job_response.status_code == 200
    quick_job_payload = quick_job_response.json()
    assert quick_job_payload["status"] == "completed"
    assert quick_job_payload["website_id"] == str(website_id)

    assert len(calls) == 2
    for call in calls:
        assert call["skill"] == "web-save"
        assert call["script"] == "save_url.py"
        assert call["args"] == [url, "--database", "--user-id", TEST_USER_ID]
        assert call["user_id"] == TEST_USER_ID


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
