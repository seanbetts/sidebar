from datetime import UTC, datetime

from api.services.agent.conversation_compaction_service import (
    ConversationCompactionService,
)
from api.services.conversation_service import ConversationService


def test_compact_conversation_history_hides_source_messages_and_appends_summary(
    test_db,
):
    conversation = ConversationService.create_conversation(
        test_db,
        "user-1",
        "Chat",
    )
    timestamp = datetime.now(UTC).isoformat()
    ConversationService.add_messages(
        test_db,
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
        ],
    )

    updated = ConversationCompactionService.compact_conversation_history(
        db=test_db,
        user_id="user-1",
        conversation_id=conversation.id,
        replay_messages_to_compact=2,
        timestamp=timestamp,
        summary_message_id="summary-1",
    )

    assert updated.message_count == 1
    assert updated.first_message == "Recent question"
    assert updated.messages[0]["kind"] == "conversation_bootstrap"
    assert updated.messages[1]["visibility"] == "hidden"
    assert updated.messages[1]["compaction"]["status"] == "compacted"
    assert updated.messages[1]["compaction"]["summary_message_id"] == "summary-1"
    assert updated.messages[2]["visibility"] == "hidden"
    assert updated.messages[2]["compaction"]["status"] == "compacted"
    assert updated.messages[3]["id"] == "summary-1"
    assert updated.messages[3]["visibility"] == "hidden"
    assert updated.messages[3]["kind"] == "conversation_compaction_summary"
    assert updated.messages[3]["compaction"]["status"] == "summary"
    assert updated.messages[3]["compaction"]["source_message_ids"] == [
        "msg-user-1",
        "msg-assistant-1",
    ]
    assert "Old question" in updated.messages[3]["content"]
    assert "Old answer" in updated.messages[3]["content"]
    assert updated.messages[4]["content"] == "Recent question"
