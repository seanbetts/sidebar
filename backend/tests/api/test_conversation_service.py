from datetime import UTC, datetime

import pytest
from api.services.conversation_service import ConversationService


@pytest.fixture
def db_session(test_db):
    return test_db


def test_create_and_list_conversations(db_session):
    conversation = ConversationService.create_conversation(
        db_session, "user-1", "New Chat"
    )
    results = ConversationService.list_conversations(db_session, "user-1")

    assert any(item.id == conversation.id for item in results)


def test_add_message_updates_metadata(db_session):
    conversation = ConversationService.create_conversation(db_session, "user-1", "Chat")
    payload = {
        "id": "msg-1",
        "role": "user",
        "content": "Hello there",
        "status": None,
        "timestamp": datetime.now(UTC).isoformat(),
        "toolCalls": None,
        "error": None,
    }

    updated = ConversationService.add_message(
        db_session, "user-1", conversation.id, payload
    )

    assert updated.message_count == 1
    assert updated.first_message == "Hello there"


def test_add_messages_appends_batch_in_order(db_session):
    conversation = ConversationService.create_conversation(db_session, "user-1", "Chat")
    timestamp = datetime.now(UTC).isoformat()
    updated = ConversationService.add_messages(
        db_session,
        "user-1",
        conversation.id,
        [
            {
                "id": "msg-user-1",
                "role": "user",
                "content": "Hello there",
                "status": "complete",
                "timestamp": timestamp,
            },
            {
                "id": "msg-assistant-1",
                "role": "assistant",
                "content": "Hi back",
                "status": "complete",
                "timestamp": timestamp,
                "toolCalls": [],
            },
        ],
    )

    assert updated.message_count == 2
    assert updated.messages[0]["id"] == "msg-user-1"
    assert updated.messages[1]["id"] == "msg-assistant-1"
    assert updated.first_message == "Hello there"


def test_add_messages_excludes_hidden_bootstrap_from_visible_metadata(db_session):
    conversation = ConversationService.create_conversation(db_session, "user-1", "Chat")
    timestamp = datetime.now(UTC).isoformat()

    updated = ConversationService.add_messages(
        db_session,
        "user-1",
        conversation.id,
        [
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
                "content": "Hello there",
                "status": "complete",
                "timestamp": timestamp,
            },
            {
                "id": "msg-assistant-1",
                "role": "assistant",
                "content": "Hi back",
                "status": "complete",
                "timestamp": timestamp,
                "toolCalls": [],
            },
        ],
    )

    assert len(updated.messages) == 3
    assert updated.message_count == 2
    assert updated.first_message == "Hello there"


def test_search_conversations(db_session):
    title_match = ConversationService.create_conversation(
        db_session, "user-1", "Alpha Chat"
    )
    message_match = ConversationService.create_conversation(
        db_session, "user-1", "Other Chat"
    )

    ConversationService.add_message(
        db_session,
        "user-1",
        message_match.id,
        {
            "id": "msg-2",
            "role": "assistant",
            "content": "Delta response",
            "status": None,
            "timestamp": datetime.now(UTC).isoformat(),
            "toolCalls": None,
            "error": None,
        },
    )

    title_results = ConversationService.search_conversations(
        db_session, "user-1", "Alpha", limit=10
    )
    message_results = ConversationService.search_conversations(
        db_session, "user-1", "Delta", limit=10
    )

    assert any(item.id == title_match.id for item in title_results)
    assert any(item.id == message_match.id for item in message_results)


def test_search_conversations_ignores_hidden_messages(db_session):
    hidden_only = ConversationService.create_conversation(
        db_session,
        "user-1",
        "Hidden Chat",
    )
    visible_match = ConversationService.create_conversation(
        db_session,
        "user-1",
        "Visible Chat",
    )

    ConversationService.add_messages(
        db_session,
        "user-1",
        hidden_only.id,
        [
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
    )
    ConversationService.add_message(
        db_session,
        "user-1",
        visible_match.id,
        {
            "id": "msg-visible-1",
            "role": "assistant",
            "content": "Visible search phrase",
            "status": "complete",
            "timestamp": datetime.now(UTC).isoformat(),
            "toolCalls": [],
        },
    )

    hidden_results = ConversationService.search_conversations(
        db_session,
        "user-1",
        "Secret bootstrap phrase",
        limit=10,
    )
    visible_results = ConversationService.search_conversations(
        db_session,
        "user-1",
        "Visible search phrase",
        limit=10,
    )

    assert all(item.id != hidden_only.id for item in hidden_results)
    assert any(item.id == visible_match.id for item in visible_results)


def test_archive_conversation_excluded_from_list(db_session):
    conversation = ConversationService.create_conversation(
        db_session, "user-1", "Archive Me"
    )
    ConversationService.update_conversation(
        db_session,
        "user-1",
        conversation.id,
        is_archived=True,
    )

    results = ConversationService.list_conversations(db_session, "user-1")
    assert all(item.id != conversation.id for item in results)
