from types import SimpleNamespace

import pytest
from api.services.claude_streaming import stream_with_tools


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

    def stream(self, **kwargs):
        self.called_args = kwargs
        return FakeStream(self._events)


class FakeClient:
    def __init__(self, events):
        self.messages = FakeMessages(events)


class DummyToolMapper:
    def __init__(self):
        self.calls = []

    def get_claude_tools(self, allowed_skills=None):
        return []

    def get_tool_display_name(self, name):
        return "Test Tool"

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
