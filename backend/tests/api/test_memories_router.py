from api.config import settings
from tests.helpers import error_message


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_memories_create_rejects_invalid_path(test_client):
    response = test_client.post(
        "/api/memories",
        json={"path": "..", "content": "test"},
        headers=_auth_headers(),
    )
    assert response.status_code == 400
    assert "Invalid path" in error_message(response)


def test_memories_create_and_list(test_client):
    response = test_client.post(
        "/api/memories",
        json={"path": "/memories/test.md", "content": "hello"},
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    created = response.json()
    assert created["path"] == "/memories/test.md"

    list_response = test_client.get("/api/memories", headers=_auth_headers())
    assert list_response.status_code == 200
    assert any(item["id"] == created["id"] for item in list_response.json())


def test_memories_update_and_delete(test_client):
    response = test_client.post(
        "/api/memories",
        json={"path": "/memories/update.md", "content": "hello"},
        headers=_auth_headers(),
    )
    memory_id = response.json()["id"]

    update = test_client.patch(
        f"/api/memories/{memory_id}",
        json={"content": "updated"},
        headers=_auth_headers(),
    )
    assert update.status_code == 200
    assert update.json()["content"] == "updated"

    delete = test_client.delete(f"/api/memories/{memory_id}", headers=_auth_headers())
    assert delete.status_code == 200
    assert delete.json()["success"] is True
