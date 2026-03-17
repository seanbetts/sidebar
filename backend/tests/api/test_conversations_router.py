import os
import uuid
from datetime import UTC, datetime

import pytest

from api.config import settings
from api.db.dependencies import get_current_user_id
from api.main import app
from api.middleware import rate_limit as rate_limit_module
from api.models.conversation import Conversation

TEST_USER_ID = os.environ["TEST_USER_ID"]


@pytest.fixture(autouse=True)
def _reset_rate_limiter():
    rate_limit_module.rate_limiter.reset()
    yield
    rate_limit_module.rate_limiter.reset()


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
        user_id=TEST_USER_ID,
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


def test_conversation_search_rate_limit_is_user_scoped(test_client, monkeypatch):
    monkeypatch.setitem(
        rate_limit_module.RATE_LIMIT_POLICIES,
        "conversation_search",
        rate_limit_module.RateLimitPolicy(limit=1, window_seconds=60),
    )
    rate_limit_module.rate_limiter.reset()

    app.dependency_overrides[get_current_user_id] = lambda: "search-user-1"
    try:
        first = test_client.post(
            "/api/conversations/search",
            params={"query": "hello"},
            headers=_auth_headers(),
        )
        second = test_client.post(
            "/api/conversations/search",
            params={"query": "hello again"},
            headers=_auth_headers(),
        )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    app.dependency_overrides[get_current_user_id] = lambda: "search-user-2"
    try:
        third = test_client.post(
            "/api/conversations/search",
            params={"query": "hello from another user"},
            headers=_auth_headers(),
        )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        rate_limit_module.rate_limiter.reset()

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["error"]["code"] == "RATE_LIMITED"
    assert second.json()["error"]["details"]["scope"] == "conversation_search"
    assert second.headers["Retry-After"]
    assert third.status_code == 200


def test_conversation_messages_and_delete(test_client, test_db):
    conversation_id = uuid.uuid4()
    conversation = Conversation(
        id=conversation_id,
        user_id=TEST_USER_ID,
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


def test_get_conversation_hides_hidden_bootstrap_messages(test_client, test_db):
    conversation_id = uuid.uuid4()
    conversation = Conversation(
        id=conversation_id,
        user_id=TEST_USER_ID,
        title="Chat",
        messages=[
            {
                "id": "bootstrap-1",
                "role": "user",
                "content": "I am Sam.",
                "status": "complete",
                "timestamp": datetime.now(UTC).isoformat(),
                "visibility": "hidden",
                "kind": "conversation_bootstrap",
            },
            {
                "id": "msg-1",
                "role": "user",
                "content": "Hello",
                "status": None,
                "timestamp": datetime.now(UTC).isoformat(),
                "toolCalls": None,
                "error": None,
            },
        ],
        message_count=1,
        first_message="Hello",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(conversation)
    test_db.commit()

    response = test_client.get(
        f"/api/conversations/{conversation_id}",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["messageCount"] == 1
    assert payload["messages"] == [
        {
            "id": "msg-1",
            "role": "user",
            "content": "Hello",
            "status": None,
            "timestamp": conversation.messages[1]["timestamp"],
            "toolCalls": None,
            "error": None,
        }
    ]


def test_search_conversations_ignores_hidden_bootstrap_messages(test_client, test_db):
    hidden_conversation_id = uuid.uuid4()
    visible_conversation_id = uuid.uuid4()
    hidden_conversation = Conversation(
        id=hidden_conversation_id,
        user_id=TEST_USER_ID,
        title="Hidden Chat",
        messages=[
            {
                "id": "bootstrap-1",
                "role": "user",
                "content": "Secret bootstrap phrase",
                "status": "complete",
                "timestamp": datetime.now(UTC).isoformat(),
                "visibility": "hidden",
                "kind": "conversation_bootstrap",
            }
        ],
        message_count=0,
        first_message=None,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    visible_conversation = Conversation(
        id=visible_conversation_id,
        user_id=TEST_USER_ID,
        title="Visible Chat",
        messages=[
            {
                "id": "msg-1",
                "role": "assistant",
                "content": "Visible search phrase",
                "status": "complete",
                "timestamp": datetime.now(UTC).isoformat(),
            }
        ],
        message_count=1,
        first_message="Visible search phrase",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(hidden_conversation)
    test_db.add(visible_conversation)
    test_db.commit()

    hidden_response = test_client.post(
        "/api/conversations/search",
        params={"query": "Secret bootstrap phrase"},
        headers=_auth_headers(),
    )
    visible_response = test_client.post(
        "/api/conversations/search",
        params={"query": "Visible search phrase"},
        headers=_auth_headers(),
    )

    assert hidden_response.status_code == 200
    assert visible_response.status_code == 200
    assert all(
        item["id"] != str(hidden_conversation_id)
        for item in hidden_response.json()
    )
    assert any(
        item["id"] == str(visible_conversation_id)
        for item in visible_response.json()
    )


def test_compact_conversation_persists_hidden_summary(test_client, test_db):
    conversation_id = uuid.uuid4()
    timestamp = datetime.now(UTC).isoformat()
    conversation = Conversation(
        id=conversation_id,
        user_id=TEST_USER_ID,
        title="Compaction Chat",
        messages=[
            {
                "id": "bootstrap-1",
                "role": "user",
                "content": "I am Sam.",
                "status": "complete",
                "timestamp": timestamp,
                "visibility": "hidden",
                "kind": "conversation_bootstrap",
            },
            {
                "id": "msg-user-1",
                "role": "user",
                "content": "Old question",
                "status": "complete",
                "timestamp": timestamp,
            },
            {
                "id": "msg-assistant-1",
                "role": "assistant",
                "content": "Old answer",
                "status": "complete",
                "timestamp": timestamp,
            },
            {
                "id": "msg-user-2",
                "role": "user",
                "content": "Recent question",
                "status": "complete",
                "timestamp": timestamp,
            },
            {
                "id": "msg-assistant-2",
                "role": "assistant",
                "content": "Recent answer",
                "status": "complete",
                "timestamp": timestamp,
            },
        ],
        message_count=4,
        first_message="Old question",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(conversation)
    test_db.commit()

    response = test_client.post(
        f"/api/conversations/{conversation_id}/compact",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == str(conversation_id)
    assert payload["messageCount"] == 2
    assert payload["firstMessage"] == "Recent question"

    refreshed = test_db.get(Conversation, conversation_id)
    assert refreshed is not None
    assert refreshed.message_count == 2
    assert refreshed.first_message == "Recent question"
    assert refreshed.messages[1]["visibility"] == "hidden"
    assert refreshed.messages[1]["compaction"]["status"] == "compacted"
    assert refreshed.messages[2]["visibility"] == "hidden"
    assert refreshed.messages[2]["compaction"]["status"] == "compacted"
    assert refreshed.messages[3]["kind"] == "conversation_compaction_summary"
    assert refreshed.messages[3]["visibility"] == "hidden"
    assert refreshed.messages[4]["content"] == "Recent question"
    assert refreshed.messages[5]["content"] == "Recent answer"
