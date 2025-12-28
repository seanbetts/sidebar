from api.config import settings


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_conversation_create_and_list(test_client):
    create_response = test_client.post(
        "/api/conversations/",
        json={"title": "Test Chat"},
        headers=_auth_headers(),
    )
    assert create_response.status_code == 200
    body = create_response.json()
    assert body["title"] == "Test Chat"

    list_response = test_client.get("/api/conversations/", headers=_auth_headers())
    assert list_response.status_code == 200
    items = list_response.json()
    assert any(item["id"] == body["id"] for item in items)
