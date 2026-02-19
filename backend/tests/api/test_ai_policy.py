from types import SimpleNamespace
from typing import Any

import pytest

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
    assert get_default_model("google", "chat", settings) == "gemini-3.1-pro"
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
        == "gemini-3.1-pro"
    )


@pytest.mark.asyncio
async def test_gateway_stream_chat_openai_emits_tokens_and_uses_model() -> None:
    captured: dict[str, Any] = {}

    class FakeDelta:
        def __init__(self, content: str):
            self.content = content

    class FakeChoice:
        def __init__(self, content: str):
            self.delta = FakeDelta(content)

    class FakeChunk:
        def __init__(self, content: str):
            self.choices = [FakeChoice(content)]

    class FakeStream:
        def __aiter__(self):
            self._chunks = iter([FakeChunk("Hello "), FakeChunk("world")])
            return self

        async def __anext__(self):
            try:
                return next(self._chunks)
            except StopIteration as exc:
                raise StopAsyncIteration from exc

    class FakeCompletions:
        async def create(self, **kwargs):
            captured["kwargs"] = kwargs
            return FakeStream()

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
    assert [event["content"] for event in events] == ["Hello ", "world"]
    assert captured["kwargs"]["model"] == "gpt-5.2"


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_emits_tokens_and_uses_model() -> None:
    captured: dict[str, Any] = {}

    class FakeModels:
        def generate_content(self, **kwargs):
            captured["kwargs"] = kwargs
            return SimpleNamespace(text="Google response")

    class FakeGoogleClient:
        def __init__(self):
            self.models = FakeModels()

    gateway = AIProviderGateway(
        settings,
        google_client_factory=lambda **_kwargs: FakeGoogleClient(),
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
    assert captured["kwargs"]["model"] == "gemini-3.1-pro"


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


@pytest.mark.asyncio
async def test_gateway_generate_title_anthropic_uses_locked_model(monkeypatch) -> None:
    captured: dict[str, Any] = {}

    class FakeMessages:
        async def create(self, **kwargs):
            captured["kwargs"] = kwargs
            return SimpleNamespace(
                content=[SimpleNamespace(type="text", text="Anthropic Title")]
            )

    class FakeAsyncAnthropic:
        def __init__(self, **_kwargs):
            self.messages = FakeMessages()

    from api.services.ai import gateway as gateway_module

    monkeypatch.setattr(gateway_module, "AsyncAnthropic", FakeAsyncAnthropic)
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
