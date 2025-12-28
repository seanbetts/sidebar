from api.config import settings


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_memories_create_rejects_invalid_path(test_client):
    response = test_client.post(
        "/api/memories",
        json={"path": "..", "content": "test"},
        headers=_auth_headers(),
    )
    assert response.status_code == 400
    assert "Invalid path" in response.json()["detail"]
