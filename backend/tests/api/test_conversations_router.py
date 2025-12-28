from datetime import datetime, timezone
import uuid

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
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
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
