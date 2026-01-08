import uuid
from datetime import UTC, datetime

from api.config import settings
from api.db.dependencies import DEFAULT_USER_ID
from api.models.conversation import Conversation


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


def test_conversation_update_and_search(test_client, test_db):
    conversation_id = uuid.uuid4()
    conversation = Conversation(
        id=conversation_id,
        user_id=DEFAULT_USER_ID,
        title="Project Plan",
        messages=[{"role": "user", "content": "hello"}],
        message_count=1,
        first_message="hello",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(conversation)
    test_db.commit()

    update_response = test_client.put(
        f"/api/conversations/{conversation_id}",
        json={"title": "Updated Plan", "isArchived": False},
        headers=_auth_headers(),
    )
    assert update_response.status_code == 200

    search_response = test_client.post(
        "/api/conversations/search",
        params={"query": "Updated"},
        headers=_auth_headers(),
    )
    assert search_response.status_code == 200
    assert any(item["id"] == str(conversation_id) for item in search_response.json())


def test_conversation_messages_and_delete(test_client, test_db):
    conversation_id = uuid.uuid4()
    conversation = Conversation(
        id=conversation_id,
        user_id=DEFAULT_USER_ID,
        title="Chat",
        messages=[],
        message_count=0,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(conversation)
    test_db.commit()

    message = {
        "id": "msg-1",
        "role": "user",
        "content": "Hello",
        "status": None,
        "timestamp": datetime.now(UTC).isoformat(),
        "toolCalls": None,
        "error": None,
    }
    response = test_client.post(
        f"/api/conversations/{conversation_id}/messages",
        json=message,
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    assert response.json()["messageCount"] == 1

    delete_response = test_client.delete(
        f"/api/conversations/{conversation_id}",
        headers=_auth_headers(),
    )
    assert delete_response.status_code == 200

    list_response = test_client.get("/api/conversations/", headers=_auth_headers())
    assert list_response.status_code == 200
    assert all(item["id"] != str(conversation_id) for item in list_response.json())
