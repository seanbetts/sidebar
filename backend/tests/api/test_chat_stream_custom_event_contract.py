from api.services.agent.orchestrator.event_emitter import ONBOARDING_STREAM_EVENT_TYPES
from api.services.ai.chat_stream_sync_protocol import CUSTOM_CHAT_STREAM_EVENT_TYPES


def test_chat_stream_sync_protocol_matches_expected_event_set() -> None:
    expected_event_types = {
        "collection_invalidated",
        "entity_changed",
        "entity_deleted",
        "prompt_preview",
        "tool_confirmation_requested",
        "tool_confirmation_resolved",
        "tool_status",
        "undo_available",
        "workspace_patch",
    }
    assert CUSTOM_CHAT_STREAM_EVENT_TYPES == expected_event_types


def test_onboarding_stream_events_remain_separate_from_tool_sync_events() -> None:
    assert ONBOARDING_STREAM_EVENT_TYPES == {
        "onboarding_provider_blocked",
        "onboarding_resume_suggested",
        "onboarding_milestone_completed",
    }
