from api.config import settings
from api.routers import scratchpad as scratchpad_router


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_scratchpad_ensure_title():
    content = "Hello"
    result = scratchpad_router.ensure_title(content)
    assert result.startswith(f"# {scratchpad_router.SCRATCHPAD_TITLE}")


def test_scratchpad_get_returns_note(test_client):
    response = test_client.get("/api/scratchpad", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == scratchpad_router.SCRATCHPAD_TITLE


def test_scratchpad_update_roundtrip(test_client):
    response = test_client.post(
        "/api/scratchpad",
        json={"content": "Hello"},
        headers=_auth_headers(),
    )
    assert response.status_code == 200

    updated = test_client.get("/api/scratchpad", headers=_auth_headers())
    assert updated.status_code == 200
    assert "Hello" in updated.json()["content"]
