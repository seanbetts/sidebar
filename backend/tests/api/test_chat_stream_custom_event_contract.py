import json
from pathlib import Path

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
