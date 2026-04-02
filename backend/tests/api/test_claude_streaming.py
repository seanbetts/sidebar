from types import SimpleNamespace

import pytest
from api.services.agent.orchestrator.stream_runner import stream_with_tools


class FakeStream:
    def __init__(self, events):
        self._events = events

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    def __aiter__(self):
        async def _gen():
            for event in self._events:
                yield event

        return _gen()


class FakeMessages:
    def __init__(self, events):
        self._events = events
        self.called_args = None
        self.called_args_history = []

    def stream(self, **kwargs):
        self.called_args = kwargs
        self.called_args_history.append(kwargs)
        return FakeStream(self._events)


class FakeClient:
    def __init__(self, events, messages=None):
        self.messages = messages or FakeMessages(events)


class FailThenStreamMessages(FakeMessages):
    def __init__(self, events, message="Connection error."):
        super().__init__(events)
        self._failed = False
        self._message = message

    def stream(self, **kwargs):
        self.called_args = kwargs
        self.called_args_history.append(kwargs)
        if not self._failed:
            self._failed = True
            raise RuntimeError(self._message)
        return FakeStream(self._events)


class DummyToolMapper:
    def __init__(self):
        self.calls = []

    def get_claude_tools(self, allowed_skills=None):
        return []

    def get_tool_display_name(self, name):
        return "Test Tool"

    def get_tool_skill_id(self, name):
        _ = name
        return None

    def get_tool_icon_key(self, name):
        _ = name
        return None

    async def execute_tool(self, name, input, allowed_skills=None, context=None):
        self.calls.append((name, input))
        return {"success": True, "data": {"id": "note-1"}}


@pytest.mark.asyncio
async def test_stream_with_tools_emits_tokens():
    events = [
        SimpleNamespace(
            type="content_block_start", content_block=SimpleNamespace(type="text")
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(type="text_delta", text="Hello"),
        ),
        SimpleNamespace(type="message_stop"),
    ]
    client = FakeClient(events)
    tool_mapper = DummyToolMapper()

    output = []
    async for event in stream_with_tools(
        client=client,
        tool_mapper=tool_mapper,
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    tokens = [item for item in output if item.get("type") == "token"]
    assert tokens == [{"type": "token", "content": "Hello"}]


@pytest.mark.asyncio
async def test_stream_with_tools_handles_tool_use():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"foo": "bar"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]
    client = FakeClient(events)
    tool_mapper = DummyToolMapper()

    output = []
    async for event in stream_with_tools(
        client=client,
        tool_mapper=tool_mapper,
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    event_types = [item["type"] for item in output]
    assert "tool_call" in event_types
    assert "tool_result" in event_types
    assert tool_mapper.calls
    assert tool_mapper.calls[-1] == ("test_tool", {"foo": "bar"})


@pytest.mark.asyncio
async def test_stream_with_tools_emits_skill_metadata_for_tool_events():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"foo": "bar"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class SkillMetadataToolMapper(DummyToolMapper):
        def get_tool_skill_id(self, name):
            _ = name
            return "notes"

        def get_tool_icon_key(self, name):
            _ = name
            return "notes"

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=SkillMetadataToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    tool_call = next(item for item in output if item.get("type") == "tool_call")
    tool_result = next(item for item in output if item.get("type") == "tool_result")
    assert tool_call["skill_id"] == "notes"
    assert tool_call["icon_key"] == "notes"
    assert tool_result["skill_id"] == "notes"
    assert tool_result["icon_key"] == "notes"


@pytest.mark.asyncio
async def test_stream_with_tools_handles_bad_tool_json():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(type="input_json_delta", partial_json="{"),
        ),
        SimpleNamespace(type="message_stop"),
    ]
    client = FakeClient(events)
    tool_mapper = DummyToolMapper()

    output = []
    async for event in stream_with_tools(
        client=client,
        tool_mapper=tool_mapper,
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert tool_mapper.calls[-1] == ("test_tool", {})
    assert any(item["type"] == "tool_result" for item in output)


@pytest.mark.asyncio
async def test_stream_with_tools_emits_memory_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(type="tool_use", id="tool-1", name="memory"),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"command": "create"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class MemoryToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Memory Tool"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {"success": True, "data": {"command": "create", "content": "ok"}}

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=MemoryToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert any(item["type"] == "memory_created" for item in output)


@pytest.mark.asyncio
async def test_stream_with_tools_emits_assistant_identity_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="assistant_identity"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"name": "Navigator"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class AssistantIdentityToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Update Assistant Identity"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {
                "success": True,
                "data": {
                    "assistant_identity": {"name": "Navigator"},
                    "assistant_identity_meta": {
                        "updated_at": "2026-02-18T00:00:00Z",
                        "version": 3,
                    },
                },
            }

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=AssistantIdentityToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert {
        "type": "assistant_identity_updated",
        "data": {
            "assistant_identity": {"name": "Navigator"},
            "assistant_identity_meta": {
                "updated_at": "2026-02-18T00:00:00Z",
                "version": 3,
            },
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_assistant_soul_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="assistant_soul"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"purpose": "Help"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class AssistantSoulToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Reset Assistant Soul"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {
                "success": True,
                "data": {
                    "assistant_soul": {"purpose": "Help"},
                    "assistant_soul_meta": {
                        "updated_at": "2026-02-18T00:00:00Z",
                        "version": 4,
                    },
                },
            }

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=AssistantSoulToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert {
        "type": "assistant_soul_updated",
        "data": {
            "assistant_soul": {"purpose": "Help"},
            "assistant_soul_meta": {
                "updated_at": "2026-02-18T00:00:00Z",
                "version": 4,
            },
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_profile_user_settings_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="profile_user_settings"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"name": "Sean"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class ProfileUserSettingsToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Update Profile and User Settings"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {
                "success": True,
                "data": {
                    "settings": {
                        "name": "Sean",
                        "job_title": "Engineer",
                        "location": "Austin, TX",
                    }
                },
            }

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=ProfileUserSettingsToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert {
        "type": "profile_user_settings_updated",
        "data": {
            "name": "Sean",
            "job_title": "Engineer",
            "location": "Austin, TX",
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_other_preferences_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="other_preferences"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"weather_unit": "fahrenheit"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class OtherPreferencesToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Set Other Preferences"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {
                "success": True,
                "data": {
                    "weather_unit": "fahrenheit",
                    "biometric_unlock_enabled": True,
                },
            }

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=OtherPreferencesToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert {
        "type": "other_preferences_updated",
        "data": {
            "weather_unit": "fahrenheit",
            "biometric_unlock_enabled": True,
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_onboarding_provider_blocked_event():
    events = [
        SimpleNamespace(
            type="content_block_start", content_block=SimpleNamespace(type="text")
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(type="text_delta", text="Let's finish setup."),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=DummyToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=["onboarding-coach"],
        tool_context={
            "onboarding_state": {
                "status": "dismissed",
                "provider_ready": False,
                "current_onboarding_step": "provider_recovery",
                "is_onboarding_complete": False,
            }
        },
    ):
        output.append(event)

    assert {
        "type": "onboarding_provider_blocked",
        "data": {
            "current_onboarding_step": "provider_recovery",
            "provider_ready": False,
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_onboarding_resume_suggested_event():
    events = [
        SimpleNamespace(
            type="content_block_start", content_block=SimpleNamespace(type="text")
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(type="text_delta", text="Resume onboarding."),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=DummyToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=["onboarding-coach"],
        tool_context={
            "onboarding_state": {
                "status": "in_progress",
                "provider_ready": True,
                "current_onboarding_step": "feature_discovery",
                "is_onboarding_complete": False,
            }
        },
    ):
        output.append(event)

    assert {
        "type": "onboarding_resume_suggested",
        "data": {
            "current_onboarding_step": "feature_discovery",
            "provider_ready": True,
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_onboarding_milestone_completed_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"step": "next"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class MilestoneToolMapper(DummyToolMapper):
        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {
                "success": True,
                "data": {
                    "onboarding_milestone": "provider_connected",
                },
            }

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=MilestoneToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=["onboarding-coach"],
        tool_context={
            "onboarding_state": {
                "status": "in_progress",
                "provider_ready": True,
                "current_onboarding_step": "feature_discovery",
                "is_onboarding_complete": False,
            }
        },
    ):
        output.append(event)

    assert {
        "type": "onboarding_milestone_completed",
        "data": {
            "current_onboarding_step": "feature_discovery",
            "provider_ready": True,
            "milestone": "provider_connected",
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_uses_updated_onboarding_state_for_first_outcome_milestone():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"title": "Test"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class MilestoneToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            _ = name
            return "Create Note"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {
                "success": True,
                "data": {
                    "id": "note-1",
                    "title": "Test",
                    "onboarding_milestone": "first_outcome_completed",
                    "onboarding_state": {
                        "status": "in_progress",
                        "provider_ready": True,
                        "current_onboarding_step": "completed",
                        "is_onboarding_complete": True,
                    },
                },
            }

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=MilestoneToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=["notes"],
        tool_context={
            "onboarding_state": {
                "status": "in_progress",
                "provider_ready": True,
                "current_onboarding_step": "feature_discovery",
                "is_onboarding_complete": False,
            }
        },
    ):
        output.append(event)

    assert {
        "type": "onboarding_milestone_completed",
        "data": {
            "current_onboarding_step": "completed",
            "provider_ready": True,
            "milestone": "first_outcome_completed",
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_note_pinned_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"note_id": "note-1"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class PinNoteToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Pin Note"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {"success": True, "data": {"id": "note-1", "pinned": True}}

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=PinNoteToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert any(item["type"] == "note_pinned" for item in output)


@pytest.mark.asyncio
async def test_stream_with_tools_emits_note_created_workspace_open_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"title": "Created from chat"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class CreateNoteToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Create Note"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {
                "success": True,
                "data": {
                    "id": "note-1",
                    "title": "Created from chat",
                    "folder": "",
                    "path": "note-1",
                },
            }

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=CreateNoteToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert {
        "type": "note_created",
        "data": {
            "id": "note-1",
            "title": "Created from chat",
            "folder": "",
            "path": "note-1",
            "open_in_workspace": True,
        },
    } in output


@pytest.mark.asyncio
async def test_stream_with_tools_emits_ingestion_updated_event():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"path": "files/test.txt"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class WriteFileToolMapper(DummyToolMapper):
        def get_tool_display_name(self, name):
            return "Write File"

        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            return {"success": True, "data": {"file_id": "file-123"}}

    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=WriteFileToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert any(item["type"] == "ingestion_updated" for item in output)


@pytest.mark.asyncio
async def test_stream_with_tools_emits_error_on_exception():
    events = [
        SimpleNamespace(
            type="content_block_start",
            content_block=SimpleNamespace(
                type="tool_use", id="tool-1", name="test_tool"
            ),
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(
                type="input_json_delta", partial_json='{"foo": "bar"}'
            ),
        ),
        SimpleNamespace(type="message_stop"),
    ]

    class FailingToolMapper(DummyToolMapper):
        async def execute_tool(self, name, input, allowed_skills=None, context=None):
            raise RuntimeError("boom")

    class DummyDB:
        def __init__(self):
            self.rolled_back = False

        def rollback(self):
            self.rolled_back = True

    dummy_db = DummyDB()
    output = []
    async for event in stream_with_tools(
        client=FakeClient(events),
        tool_mapper=FailingToolMapper(),
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
        tool_context={"db": dummy_db},
    ):
        output.append(event)

    assert output[-1]["type"] == "error"
    assert output[-1]["error"] == "boom"
    assert dummy_db.rolled_back is True


@pytest.mark.asyncio
async def test_stream_with_tools_retries_without_optional_features_on_connection_error():
    events = [
        SimpleNamespace(
            type="content_block_start", content_block=SimpleNamespace(type="text")
        ),
        SimpleNamespace(
            type="content_block_delta",
            delta=SimpleNamespace(type="text_delta", text="Hello"),
        ),
        SimpleNamespace(type="message_stop"),
    ]
    messages = FailThenStreamMessages(events)
    client = FakeClient(events, messages=messages)
    tool_mapper = DummyToolMapper()

    output = []
    async for event in stream_with_tools(
        client=client,
        tool_mapper=tool_mapper,
        model="test-model",
        message="Hi",
        conversation_history=[],
    ):
        output.append(event)

    assert [item for item in output if item.get("type") == "token"] == [
        {"type": "token", "content": "Hello"}
    ]
    assert len(messages.called_args_history) == 2

    first_call = messages.called_args_history[0]
    second_call = messages.called_args_history[1]

    assert first_call["extra_headers"] == {
        "anthropic-beta": "context-management-2025-06-27"
    }
    assert any(tool.get("type") == "web_search_20250305" for tool in first_call["tools"])
    assert "extra_headers" not in second_call
    assert not any(
        tool.get("type") == "web_search_20250305" for tool in second_call["tools"]
    )


@pytest.mark.asyncio
async def test_stream_with_tools_does_not_retry_without_optional_features():
    messages = FailThenStreamMessages([])
    client = FakeClient([], messages=messages)
    tool_mapper = DummyToolMapper()

    output = []
    async for event in stream_with_tools(
        client=client,
        tool_mapper=tool_mapper,
        model="test-model",
        message="Hi",
        conversation_history=[],
        allowed_skills=[],
    ):
        output.append(event)

    assert output == [{"type": "error", "error": "Connection error."}]
    assert len(messages.called_args_history) == 1
