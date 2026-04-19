import json
from pathlib import Path

from api.services.ai import chat_stream_custom_events
from api.services.ai.chat_stream_custom_events import CUSTOM_CHAT_STREAM_EVENT_TYPES


def test_custom_chat_stream_contract_matches_expected_event_set() -> None:
    contract_path = (
        Path(__file__).resolve().parents[3]
        / "shared"
        / "contracts"
        / "chat_stream_custom_events.json"
    )
    assert contract_path.exists(), "Missing shared custom SSE event contract"

    contract = json.loads(contract_path.read_text())

    expected_event_types = {
        "assistant_identity_updated",
        "assistant_soul_updated",
        "conversation_title_updated",
        "ingestion_updated",
        "memory_created",
        "memory_deleted",
        "memory_updated",
        "note_created",
        "note_deleted",
        "note_moved",
        "note_pinned",
        "note_updated",
        "onboarding_milestone_completed",
        "onboarding_provider_blocked",
        "onboarding_resume_suggested",
        "other_preferences_updated",
        "profile_user_settings_updated",
        "prompt_preview",
        "scratchpad_cleared",
        "scratchpad_updated",
        "tool_end",
        "tool_start",
        "ui_theme_set",
        "website_archived",
        "website_deleted",
        "website_pinned",
        "website_renamed",
        "website_saved",
        "workspace_patch",
    }
    assert set(contract["custom_events"]) == expected_event_types
    assert CUSTOM_CHAT_STREAM_EVENT_TYPES == expected_event_types


def test_custom_chat_stream_event_types_fall_back_when_contract_file_missing(
    monkeypatch,
) -> None:
    missing_path = Path("/tmp/sidebar-missing-chat-stream-contract.json")

    chat_stream_custom_events.load_custom_chat_stream_event_types.cache_clear()
    monkeypatch.setattr(chat_stream_custom_events, "_contract_path", lambda: missing_path)

    assert (
        chat_stream_custom_events.load_custom_chat_stream_event_types()
        == CUSTOM_CHAT_STREAM_EVENT_TYPES
    )
