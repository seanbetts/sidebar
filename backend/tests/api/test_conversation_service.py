import uuid
from datetime import UTC, datetime

import pytest
from api.db.base import Base
from api.services.conversation_service import ConversationService
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker


@pytest.fixture
def db_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    )
    schema = f"test_{uuid.uuid4().hex}"

    connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    connection.execute(text(f'SET search_path TO "{schema}"'))
    Base.metadata.create_all(bind=connection)

    Session = sessionmaker(bind=connection)
    session = Session()

    try:
        yield session
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()


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
