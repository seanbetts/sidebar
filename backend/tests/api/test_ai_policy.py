from types import SimpleNamespace
from typing import Any

import pytest
from google.genai import types

from api.config import settings
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.registry import AIProvider, get_default_model
from api.services.ai.policy import (
    AICapabilityUnavailableError,
    AIPolicyService,
    AIUserPolicy,
)


def test_policy_requires_primary_provider_when_unset() -> None:
    with pytest.raises(AICapabilityUnavailableError):
        AIPolicyService.select_provider(
            "audio_transcription",
            AIUserPolicy(primary_provider=None),
        )


def test_policy_uses_primary_provider_when_supported() -> None:
    selection = AIPolicyService.select_provider(
        "title",
        AIUserPolicy(primary_provider="anthropic"),
    )
    assert selection.provider == "anthropic"


def test_policy_supports_chat_for_all_main_providers() -> None:
    providers: tuple[AIProvider, ...] = ("anthropic", "openai", "google")
    for provider in providers:
        selection = AIPolicyService.select_provider(
            "chat",
            AIUserPolicy(primary_provider=provider),
        )
        assert selection.provider == provider


def test_policy_raises_when_primary_unsupported() -> None:
    with pytest.raises(AICapabilityUnavailableError):
        AIPolicyService.select_provider(
            "audio_transcription",
            AIUserPolicy(primary_provider="google"),
        )


def test_default_model_matrix_matches_locked_policy() -> None:
    assert get_default_model("anthropic", "chat", settings) == "claude-sonnet-4-6"
    assert get_default_model("anthropic", "title", settings) == "claude-haiku-4-5"
    assert get_default_model("openai", "chat", settings) == "gpt-5.2"
    assert get_default_model("openai", "title", settings) == "gpt-5-nano"
    assert get_default_model("google", "chat", settings) == "gemini-3.1-pro-preview"
    assert get_default_model("google", "title", settings) == "gemini-3-flash-preview"
    assert (
        get_default_model("openai", "audio_transcription", settings)
        == "gpt-4o-transcribe"
    )


def test_gateway_resolve_chat_returns_provider_model_and_key() -> None:
    gateway = AIProviderGateway(settings)
    provider_keys = {
        "anthropic": "sk-anthropic-test",
        "openai": "sk-openai-test",
        "google": "sk-google-test",
    }
    for provider in ("anthropic", "openai", "google"):
        resolution = gateway.resolve_chat(
            settings_record=SimpleNamespace(ai_primary_provider=provider),
            provider_key_lookup=lambda p: provider_keys[p],
        )
        assert resolution.provider == provider
        assert resolution.api_key == provider_keys[provider]
    assert (
        gateway.resolve_chat(
            settings_record=SimpleNamespace(ai_primary_provider="anthropic"),
            provider_key_lookup=lambda _provider: "sk-anthropic-test",
        ).model
        == "claude-sonnet-4-6"
    )
    assert (
        gateway.resolve_chat(
            settings_record=SimpleNamespace(ai_primary_provider="openai"),
            provider_key_lookup=lambda _provider: "sk-openai-test",
        ).model
        == "gpt-5.2"
    )
    assert (
        gateway.resolve_chat(
            settings_record=SimpleNamespace(ai_primary_provider="google"),
            provider_key_lookup=lambda _provider: "sk-google-test",
        ).model
        == "gemini-3.1-pro-preview"
    )


@pytest.mark.asyncio
async def test_gateway_stream_chat_openai_emits_tokens_and_uses_model(monkeypatch) -> None:
    captured: dict[str, Any] = {}
    call_kwargs: list[dict[str, Any]] = []

    class FakeCompletions:
        async def create(self, **kwargs):
            call_kwargs.append(kwargs)
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(content="Hello world", tool_calls=[])
                    )
                ]
            )

    class FakeChat:
        def __init__(self):
            self.completions = FakeCompletions()

    class FakeOpenAIClient:
        def __init__(self):
            self.chat = FakeChat()

    gateway = AIProviderGateway(
        settings,
        openai_client_factory=lambda **_kwargs: FakeOpenAIClient(),
    )
    monkeypatch.setattr(
        gateway,
        "_get_tool_mapper",
        lambda: SimpleNamespace(
            get_claude_tools=lambda _allowed: [],
            get_tool_display_name=lambda name: name,
            execute_tool=None,
        ),
    )
    events = [
        event
        async for event in gateway.stream_chat_with_tools(
            message="How are you?",
            conversation_history=[{"role": "assistant", "content": "Hi"}],
            system_prompt="Be concise",
            allowed_skills=None,
            tool_context=None,
            settings_record=SimpleNamespace(ai_primary_provider="openai"),
            provider_key_lookup=lambda _provider: "sk-openai-test",
        )
    ]
    assert [event["content"] for event in events] == ["Hello world"]
    assert call_kwargs[0]["model"] == "gpt-5.2"
    captured["kwargs"] = call_kwargs[0]


@pytest.mark.asyncio
async def test_gateway_stream_chat_openai_executes_tools(monkeypatch) -> None:
    class FakeCompletions:
        def __init__(self):
            self._responses = [
                SimpleNamespace(
                    choices=[
                        SimpleNamespace(
                            message=SimpleNamespace(
                                content="",
                                tool_calls=[
                                    SimpleNamespace(
                                        id="call-1",
                                        function=SimpleNamespace(
                                            name="create_note",
                                            arguments='{"title":"Test note"}',
                                        ),
                                    )
                                ],
                            )
                        )
                    ]
                ),
                SimpleNamespace(
                    choices=[
                        SimpleNamespace(
                            message=SimpleNamespace(
                                content="Done",
                                tool_calls=[],
                            )
                        )
                    ]
                ),
            ]

        async def create(self, **_kwargs):
            return self._responses.pop(0)

    class FakeChat:
        def __init__(self):
            self.completions = FakeCompletions()

    class FakeOpenAIClient:
        def __init__(self):
            self.chat = FakeChat()

    class FakeToolMapper:
        def get_claude_tools(self, _allowed):
            return [
                {
                    "name": "create_note",
                    "description": "Create a note",
                    "input_schema": {
                        "type": "object",
                        "properties": {"title": {"type": "string"}},
                    },
                }
            ]

        def get_tool_display_name(self, name):
            return "Create Note" if name == "create_note" else name

        async def execute_tool(
            self, name, parameters, allowed_skills=None, context=None
        ):
            assert name == "create_note"
            assert parameters == {"title": "Test note"}
            assert allowed_skills is None
            assert context == {"user_id": "user-1"}
            return {
                "success": True,
                "data": {"id": "note-1", "title": "Test note", "folder": "notes"},
            }

    gateway = AIProviderGateway(
        settings,
        openai_client_factory=lambda **_kwargs: FakeOpenAIClient(),
    )
    monkeypatch.setattr(gateway, "_get_tool_mapper", lambda: FakeToolMapper())
    events = [
        event
        async for event in gateway.stream_chat_with_tools(
            message="Please create a note",
            conversation_history=[],
            system_prompt=None,
            allowed_skills=None,
            tool_context={"user_id": "user-1"},
            settings_record=SimpleNamespace(ai_primary_provider="openai"),
            provider_key_lookup=lambda _provider: "sk-openai-test",
        )
    ]
    assert any(event["type"] == "tool_call" for event in events)
    assert any(event["type"] == "tool_result" for event in events)
    assert any(event["type"] == "note_created" for event in events)
    assert any(event["type"] == "token" and event["content"] == "Done" for event in events)


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_emits_tokens_and_uses_model(monkeypatch) -> None:
    captured: dict[str, Any] = {}

    class FakeModels:
        def generate_content(self, **kwargs):
            captured["kwargs"] = kwargs
            return SimpleNamespace(text="Google response", function_calls=[])

    class FakeGoogleClient:
        def __init__(self):
            self.models = FakeModels()

    gateway = AIProviderGateway(
        settings,
        google_client_factory=lambda **_kwargs: FakeGoogleClient(),
    )
    monkeypatch.setattr(
        gateway,
        "_get_tool_mapper",
        lambda: SimpleNamespace(
            get_claude_tools=lambda _allowed: [],
            get_tool_display_name=lambda name: name,
            execute_tool=None,
        ),
    )
    events = [
        event
        async for event in gateway.stream_chat_with_tools(
            message="Summarize this",
            conversation_history=[{"role": "assistant", "content": "Context"}],
            system_prompt="Short answer",
            allowed_skills=None,
            tool_context=None,
            settings_record=SimpleNamespace(ai_primary_provider="google"),
            provider_key_lookup=lambda _provider: "sk-google-test",
        )
    ]
    assert events == [{"type": "token", "content": "Google response"}]
    assert captured["kwargs"]["model"] == "gemini-3.1-pro-preview"


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_executes_tools(monkeypatch) -> None:
    class FakeModels:
        def __init__(self):
            self._responses = [
                SimpleNamespace(
                    text="",
                    function_calls=[
                        SimpleNamespace(
                            id="google-call-1",
                            name="create_note",
                            args={"title": "Google note"},
                        )
                    ],
                    candidates=[SimpleNamespace(content=types.Content(role="model", parts=[]))],
                ),
                SimpleNamespace(text="Completed", function_calls=[], candidates=[]),
            ]

        def generate_content(self, **_kwargs):
            return self._responses.pop(0)

    class FakeGoogleClient:
        def __init__(self):
            self.models = FakeModels()

    class FakeToolMapper:
        def get_claude_tools(self, _allowed):
            return [
                {
                    "name": "create_note",
                    "description": "Create a note",
                    "input_schema": {
                        "type": "object",
                        "properties": {"title": {"type": "string"}},
                    },
                }
            ]

        def get_tool_display_name(self, name):
            return "Create Note" if name == "create_note" else name

        async def execute_tool(
            self, name, parameters, allowed_skills=None, context=None
        ):
            assert name == "create_note"
            assert parameters == {"title": "Google note"}
            assert context == {"user_id": "user-1"}
            return {
                "success": True,
                "data": {"id": "note-2", "title": "Google note", "folder": "notes"},
            }

    gateway = AIProviderGateway(
        settings,
        google_client_factory=lambda **_kwargs: FakeGoogleClient(),
    )
    monkeypatch.setattr(gateway, "_get_tool_mapper", lambda: FakeToolMapper())
    events = [
        event
        async for event in gateway.stream_chat_with_tools(
            message="Create note in google",
            conversation_history=[],
            system_prompt=None,
            allowed_skills=None,
            tool_context={"user_id": "user-1"},
            settings_record=SimpleNamespace(ai_primary_provider="google"),
            provider_key_lookup=lambda _provider: "sk-google-test",
        )
    ]
    assert any(event["type"] == "tool_call" for event in events)
    assert any(event["type"] == "tool_result" for event in events)
    assert any(event["type"] == "note_created" for event in events)
    assert any(
        event["type"] == "token" and event["content"] == "Completed" for event in events
    )


@pytest.mark.asyncio
async def test_gateway_generate_title_openai_uses_locked_model() -> None:
    captured: dict[str, Any] = {}

    class FakeCompletions:
        async def create(self, **kwargs):
            captured["kwargs"] = kwargs
            message = SimpleNamespace(content="OpenAI Title")
            choice = SimpleNamespace(message=message)
            return SimpleNamespace(choices=[choice])

    class FakeChat:
        def __init__(self):
            self.completions = FakeCompletions()

    class FakeOpenAIClient:
        def __init__(self):
            self.chat = FakeChat()

    gateway = AIProviderGateway(
        settings,
        openai_client_factory=lambda **_kwargs: FakeOpenAIClient(),
    )
    result = await gateway.generate_title(
        user_message="Plan this sprint",
        assistant_message="Let's break it down",
        settings_record=SimpleNamespace(ai_primary_provider="openai"),
        provider_key_lookup=lambda _provider: "sk-openai-test",
    )
    assert result.provider == "openai"
    assert result.raw_title == "OpenAI Title"
    assert captured["kwargs"]["model"] == "gpt-5-nano"
    assert captured["kwargs"]["max_completion_tokens"] == 64
    assert captured["kwargs"]["reasoning_effort"] == "minimal"
    assert "max_tokens" not in captured["kwargs"]
    assert "temperature" not in captured["kwargs"]


@pytest.mark.asyncio
async def test_gateway_generate_title_google_uses_locked_model() -> None:
    captured: dict[str, Any] = {}

    class FakeModels:
        def generate_content(self, **kwargs):
            captured["kwargs"] = kwargs
            return SimpleNamespace(text="Google Title")

    class FakeGoogleClient:
        def __init__(self):
            self.models = FakeModels()

    gateway = AIProviderGateway(
        settings,
        google_client_factory=lambda **_kwargs: FakeGoogleClient(),
    )
    result = await gateway.generate_title(
        user_message="Write update",
        assistant_message="Here's the summary",
        settings_record=SimpleNamespace(ai_primary_provider="google"),
        provider_key_lookup=lambda _provider: "sk-google-test",
    )
    assert result.provider == "google"
    assert result.raw_title == "Google Title"
    assert captured["kwargs"]["model"] == "gemini-3-flash-preview"
    config = captured["kwargs"]["config"]
    assert config.max_output_tokens == 64
    assert config.thinking_config.thinking_budget == 0


@pytest.mark.asyncio
async def test_gateway_generate_title_anthropic_uses_locked_model(monkeypatch) -> None:
    captured: dict[str, Any] = {}

    class FakeMessagesClient:
        async def create(self, **kwargs):
            captured["kwargs"] = kwargs
            return SimpleNamespace(
                content=[SimpleNamespace(type="text", text="Anthropic Title")]
            )

    class FakeClaudeClient:
        def __init__(self, _settings, *, api_key=None, model=None):
            assert api_key == "sk-anthropic-test"
            assert model == "claude-haiku-4-5"
            self.client = SimpleNamespace(messages=FakeMessagesClient())

    from api.services import claude_client as claude_client_module

    monkeypatch.setattr(claude_client_module, "ClaudeClient", FakeClaudeClient)
    gateway = AIProviderGateway(settings)
    result = await gateway.generate_title(
        user_message="Review roadmap",
        assistant_message="Let's prioritize",
        settings_record=SimpleNamespace(ai_primary_provider="anthropic"),
        provider_key_lookup=lambda _provider: "sk-anthropic-test",
    )
    assert result.provider == "anthropic"
    assert result.raw_title == "Anthropic Title"
    assert captured["kwargs"]["model"] == "claude-haiku-4-5"


@pytest.mark.asyncio
async def test_gateway_generate_title_google_retries_when_empty_response() -> None:
    call_count = 0

    class FakeModels:
        def generate_content(self, **_kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return SimpleNamespace(text="")
            return SimpleNamespace(text="Recovered Title")

    class FakeGoogleClient:
        def __init__(self):
            self.models = FakeModels()

    gateway = AIProviderGateway(
        settings,
        google_client_factory=lambda **_kwargs: FakeGoogleClient(),
    )
    result = await gateway.generate_title(
        user_message="Write update",
        assistant_message="Here is a summary",
        settings_record=SimpleNamespace(ai_primary_provider="google"),
        provider_key_lookup=lambda _provider: "sk-google-test",
    )
    assert call_count == 2
    assert result.provider == "google"
    assert result.raw_title == "Recovered Title"


def test_gateway_resolves_transcription_default_model() -> None:
    gateway = AIProviderGateway(settings)
    resolution = gateway.resolve_transcription(
        settings_record=SimpleNamespace(
            ai_primary_provider="openai",
        ),
        requested_model=None,
        provider_key_lookup=lambda _provider: "sk-openai-test-key",
    )
    assert resolution.provider == "openai"
    assert resolution.model == "gpt-4o-transcribe"


def test_policy_resolve_from_settings_defaults_to_strict_mode() -> None:
    policy = AIPolicyService.resolve_from_settings(None)
    assert policy.primary_provider is None


def test_gateway_resolve_transcription_respects_strict_policy() -> None:
    gateway = AIProviderGateway(settings)
    with pytest.raises(AICapabilityUnavailableError):
        gateway.resolve_transcription(
            settings_record=SimpleNamespace(
                ai_primary_provider="google",
            ),
            requested_model=None,
            provider_key_lookup=lambda _provider: "sk-openai-test-key",
        )
