from api.config import settings
from api.routers import scratchpad as scratchpad_router


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_scratchpad_ensure_title():
    content = "Hello"
    result = scratchpad_router.ensure_title(content)
    assert result.startswith(scratchpad_router.SCRATCHPAD_TITLE)
    assert not result.startswith(f"# {scratchpad_router.SCRATCHPAD_TITLE}")


def test_scratchpad_get_returns_note(test_client):
    response = test_client.get("/api/scratchpad", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == scratchpad_router.SCRATCHPAD_TITLE
    assert body["plain_text"] == scratchpad_router.SCRATCHPAD_TITLE
    assert body["content"] == scratchpad_router.SCRATCHPAD_TITLE
    assert body["document"]["blocks"][0]["type"] == "title"
    assert body["document"]["blocks"][0]["content"][0]["text"] == scratchpad_router.SCRATCHPAD_TITLE


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
    assert not updated.json()["content"].startswith(
        f"# {scratchpad_router.SCRATCHPAD_TITLE}"
    )
    assert updated.json()["document"]["blocks"][0]["type"] == "title"
    assert updated.json()["document"]["blocks"][1]["type"] == "paragraph"
    assert updated.json()["document"]["blocks"][1]["content"][0]["text"] == "Hello"


def test_scratchpad_update_roundtrip_without_write_flag(test_client):
    response = test_client.post(
        "/api/scratchpad",
        json={"content": "Strict Hello"},
        headers=_auth_headers(),
    )
    assert response.status_code == 200

    updated = test_client.get("/api/scratchpad", headers=_auth_headers())
    assert updated.status_code == 200
    assert "Strict Hello" in updated.json()["content"]
    assert not updated.json()["content"].startswith(
        f"# {scratchpad_router.SCRATCHPAD_TITLE}"
    )
    assert updated.json()["document"]["blocks"][0]["type"] == "title"
    assert all(
        block["type"] == "paragraph"
        for block in updated.json()["document"]["blocks"][1:]
    )
    assert (
        updated.json()["document"]["blocks"][-1]["content"][0]["text"] == "Strict Hello"
    )


def test_scratchpad_document_keeps_body_as_paragraph_blocks():
    document = scratchpad_router._scratchpad_document("First line\nSecond line")

    assert document == {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": scratchpad_router.SCRATCHPAD_TITLE, "marks": []}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "First line", "marks": []}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Second line", "marks": []}],
            },
        ],
    }
