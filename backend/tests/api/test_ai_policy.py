from types import SimpleNamespace
from typing import Any

import pytest
from google.genai import types

from api.config import settings
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.registry import (
    AIProvider,
    build_web_search_fallback_summary,
    get_default_model,
    supports_google_web_search,
    supports_openai_web_search,
)
from api.services.ai.tool_orchestrator import ProviderToolOrchestrator
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
    assert get_default_model("openai", "chat", settings) == "gpt-5.3-chat-latest"
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
        == "gpt-5.3-chat-latest"
    )
    assert (
        gateway.resolve_chat(
            settings_record=SimpleNamespace(ai_primary_provider="google"),
            provider_key_lookup=lambda _provider: "sk-google-test",
        ).model
        == "gemini-3.1-pro-preview"
    )


def test_google_schema_normalizer_handles_nullable_union_type() -> None:
    normalized = ProviderToolOrchestrator._normalize_google_schema(
        {
            "type": "object",
            "properties": {
                "recurrence_rule": {
                    "type": ["object", "null"],
                    "description": "Repeat rule object or null",
                }
            },
            "required": ["recurrence_rule"],
        }
    )
    recurrence_schema = normalized["properties"]["recurrence_rule"]
    assert recurrence_schema["type"] == "object"
    assert recurrence_schema["nullable"] is True


def test_google_function_declarations_normalize_input_schema() -> None:
    declarations = ProviderToolOrchestrator._build_google_function_declarations(
        [
            {
                "name": "set_task_repeat",
                "description": "Set task repeat",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "recurrence_rule": {
                            "type": ["object", "null"],
                        }
                    },
                    "required": ["recurrence_rule"],
                },
            }
        ]
    )
    recurrence_schema = declarations[0].parameters.properties["recurrence_rule"]
    assert recurrence_schema.type.value == "OBJECT"
    assert recurrence_schema.nullable is True


@pytest.mark.asyncio
async def test_gateway_stream_chat_openai_emits_tokens_and_uses_responses_api(
    monkeypatch,
) -> None:
    captured: dict[str, Any] = {}
    response_calls: list[dict[str, Any]] = []

    class FakeResponses:
        async def create(self, **kwargs):
            response_calls.append(kwargs)
            return SimpleNamespace(output_text="Hello world", output=[])

    class ForbiddenCompletions:
        async def create(self, **_kwargs):
            raise AssertionError(
                "Chat Completions should not be used for the main OpenAI chat path"
            )

    class FakeChat:
        def __init__(self):
            self.completions = ForbiddenCompletions()

    class FakeOpenAIClient:
        def __init__(self):
            self.chat = FakeChat()
            self.responses = FakeResponses()

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
    assert response_calls[0]["model"] == "gpt-5.3-chat-latest"
    assert response_calls[0]["instructions"] == "Be concise"
    assert response_calls[0]["input"] == [
        {"role": "assistant", "content": "Hi"},
        {"role": "user", "content": "How are you?"},
    ]
    captured["kwargs"] = response_calls[0]


@pytest.mark.asyncio
async def test_gateway_generate_text_openai_uses_chat_model_and_system_prompt() -> None:
    call_kwargs: list[dict[str, Any]] = []

    class FakeCompletions:
        async def create(self, **kwargs):
            call_kwargs.append(kwargs)
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(
                            content='{"assistant_identity":{"name":"Navigator"}}'
                        )
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
    result = await gateway.generate_text(
        prompt="Return JSON only.",
        system_prompt="You are writing assistant settings.",
        settings_record=SimpleNamespace(ai_primary_provider="openai"),
        provider_key_lookup=lambda _provider: "sk-openai-test",
        max_output_tokens=128,
    )

    assert result.raw_text == '{"assistant_identity":{"name":"Navigator"}}'
    assert result.provider == "openai"
    assert call_kwargs[0]["model"] == "gpt-5.3-chat-latest"
    assert call_kwargs[0]["messages"][0] == {
        "role": "system",
        "content": "You are writing assistant settings.",
    }
    assert call_kwargs[0]["messages"][1] == {
        "role": "user",
        "content": "Return JSON only.",
    }
    assert call_kwargs[0]["max_completion_tokens"] == 128
    assert call_kwargs[0]["reasoning_effort"] == "minimal"


@pytest.mark.asyncio
async def test_gateway_stream_chat_openai_executes_tools_via_responses_api(
    monkeypatch,
) -> None:
    class FakeResponses:
        def __init__(self):
            self._responses = [
                SimpleNamespace(
                    output_text="",
                    output=[
                        SimpleNamespace(
                            type="function_call",
                            call_id="call-1",
                            name="create_note",
                            arguments='{"title":"Test note"}',
                        )
                    ]
                ),
                SimpleNamespace(output_text="Done", output=[]),
            ]

        async def create(self, **_kwargs):
            return self._responses.pop(0)

    class ForbiddenCompletions:
        async def create(self, **_kwargs):
            raise AssertionError(
                "Chat Completions should not be used for the main OpenAI chat path"
            )

    class FakeChat:
        def __init__(self):
            self.completions = ForbiddenCompletions()

    class FakeOpenAIClient:
        def __init__(self):
            self.chat = FakeChat()
            self.responses = FakeResponses()

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

        def get_tool_skill_id(self, name):
            return "notes" if name == "create_note" else None

        def get_tool_icon_key(self, name):
            return "notes" if name == "create_note" else None

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
    assert any(
        event["type"] == "entity_changed"
        and event["data"]["entity_type"] == "note"
        and event["data"]["change"] == "created"
        for event in events
    )
    assert any(event["type"] == "token" and event["content"] == "Done" for event in events)
    tool_call = next(event for event in events if event["type"] == "tool_call")
    tool_result = next(event for event in events if event["type"] == "tool_result")
    assert tool_call["skill_id"] == "notes"
    assert tool_call["icon_key"] == "notes"
    assert tool_result["skill_id"] == "notes"
    assert tool_result["icon_key"] == "notes"


def test_openai_web_search_support_matches_supported_model_families() -> None:
    assert supports_openai_web_search("gpt-5.3-chat-latest") is True
    assert supports_openai_web_search("gpt-4.1-mini") is True
    assert supports_openai_web_search("gpt-4o-mini") is False


def test_google_web_search_support_requires_gemini_3_for_tool_combination() -> None:
    assert supports_google_web_search("gemini-3.1-pro-preview") is True
    assert (
        supports_google_web_search(
            "gemini-3.1-pro-preview",
            requires_tool_combination=True,
        )
        is True
    )
    assert supports_google_web_search("gemini-2.5-pro") is True
    assert (
        supports_google_web_search(
            "gemini-2.5-pro",
            requires_tool_combination=True,
        )
        is False
    )


def test_google_web_search_fallback_summary_is_provider_specific() -> None:
    summary = build_web_search_fallback_summary(
        "google",
        "gemini-2.5-pro",
        requires_tool_combination=True,
    )

    assert summary == {
        "skill_id": "web-search",
        "availability_status": "provider_model_unsupported",
        "availability_reason": (
            "Web Search with other tools is unavailable for Google model "
            "'gemini-2.5-pro'. sideBar will continue without web search. "
            "Switch to a Gemini 3 model to enable combined search and tool use."
        ),
        "availability_remediation": {
            "action": "switch_model",
            "provider": "google",
        },
    }


@pytest.mark.asyncio
async def test_gateway_stream_chat_openai_uses_responses_api_for_web_search(
    monkeypatch,
) -> None:
    captured_calls: list[dict[str, Any]] = []

    class FakeResponses:
        async def create(self, **kwargs):
            captured_calls.append(kwargs)
            return SimpleNamespace(output_text="Search answer", output=[])

    class ForbiddenCompletions:
        async def create(self, **_kwargs):
            raise AssertionError(
                "Chat Completions should not be used for OpenAI web search"
            )

    class FakeChat:
        def __init__(self):
            self.completions = ForbiddenCompletions()

    class FakeOpenAIClient:
        def __init__(self):
            self.chat = FakeChat()
            self.responses = FakeResponses()

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
            message="What's the latest Python release?",
            conversation_history=[],
            system_prompt="Be concise",
            allowed_skills=["web-search"],
            tool_context={
                "current_location_levels": {
                    "locality": "London",
                    "administrative_area_level_1": "England",
                    "country": "GB",
                },
                "current_timezone": "Europe/London",
            },
            settings_record=SimpleNamespace(ai_primary_provider="openai"),
            provider_key_lookup=lambda _provider: "sk-openai-test",
        )
    ]

    assert events == [{"type": "token", "content": "Search answer"}]
    assert len(captured_calls) == 1
    assert captured_calls[0]["model"] == "gpt-5.3-chat-latest"
    assert captured_calls[0]["include"] == ["web_search_call.action.sources"]
    assert any(
        tool.get("type") == "web_search" for tool in captured_calls[0]["tools"]
    )


@pytest.mark.asyncio
async def test_gateway_stream_chat_openai_web_search_can_execute_custom_tools(
    monkeypatch,
) -> None:
    captured_calls: list[dict[str, Any]] = []

    class FakeResponses:
        def __init__(self):
            self._responses = [
                SimpleNamespace(
                    output_text="",
                    output=[
                        SimpleNamespace(
                            type="function_call",
                            call_id="call-1",
                            name="create_note",
                            arguments='{"title":"From search"}',
                        )
                    ],
                ),
                SimpleNamespace(output_text="Done", output=[]),
            ]

        async def create(self, **kwargs):
            captured_calls.append(kwargs)
            return self._responses.pop(0)

    class ForbiddenCompletions:
        async def create(self, **_kwargs):
            raise AssertionError(
                "Chat Completions should not be used for OpenAI web search"
            )

    class FakeChat:
        def __init__(self):
            self.completions = ForbiddenCompletions()

    class FakeOpenAIClient:
        def __init__(self):
            self.chat = FakeChat()
            self.responses = FakeResponses()

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

        def get_tool_skill_id(self, name):
            return "notes" if name == "create_note" else None

        def get_tool_icon_key(self, name):
            return "notes" if name == "create_note" else None

        async def execute_tool(
            self, name, parameters, allowed_skills=None, context=None
        ):
            assert name == "create_note"
            assert parameters == {"title": "From search"}
            assert allowed_skills == ["web-search", "notes"]
            assert context == {"user_id": "user-1"}
            return {
                "success": True,
                "data": {"id": "note-search", "title": "From search"},
            }

    gateway = AIProviderGateway(
        settings,
        openai_client_factory=lambda **_kwargs: FakeOpenAIClient(),
    )
    monkeypatch.setattr(gateway, "_get_tool_mapper", lambda: FakeToolMapper())

    events = [
        event
        async for event in gateway.stream_chat_with_tools(
            message="Search the web and save the result as a note",
            conversation_history=[],
            system_prompt=None,
            allowed_skills=["web-search", "notes"],
            tool_context={"user_id": "user-1"},
            settings_record=SimpleNamespace(ai_primary_provider="openai"),
            provider_key_lookup=lambda _provider: "sk-openai-test",
        )
    ]

    assert any(event["type"] == "tool_call" for event in events)
    assert any(event["type"] == "tool_result" for event in events)
    assert any(
        event["type"] == "entity_changed"
        and event["data"]["entity_type"] == "note"
        and event["data"]["change"] == "created"
        for event in events
    )
    assert any(
        event["type"] == "token" and event["content"] == "Done" for event in events
    )
    assert any(
        tool.get("type") == "web_search" for tool in captured_calls[0]["tools"]
    )
    assert any(
        tool.get("type") == "function" and tool.get("name") == "create_note"
        for tool in captured_calls[0]["tools"]
    )


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
    assert any(
        event["type"] == "entity_changed"
        and event["data"]["entity_type"] == "note"
        and event["data"]["change"] == "created"
        for event in events
    )
    assert any(
        event["type"] == "token" and event["content"] == "Completed" for event in events
    )


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_web_search_combines_builtin_and_custom_tools(
    monkeypatch,
) -> None:
    captured_configs: list[Any] = []

    class FakeModels:
        def __init__(self):
            self._responses = [
                SimpleNamespace(
                    text="",
                    function_calls=[
                        SimpleNamespace(
                            id="google-call-search-1",
                            name="create_note",
                            args={"title": "Grounded note"},
                        )
                    ],
                    candidates=[
                        SimpleNamespace(content=types.Content(role="model", parts=[]))
                    ],
                ),
                SimpleNamespace(text="Completed", function_calls=[], candidates=[]),
            ]

        def generate_content(self, **kwargs):
            captured_configs.append(kwargs.get("config"))
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
            assert parameters == {"title": "Grounded note"}
            assert allowed_skills == ["web-search", "notes"]
            assert context == {"user_id": "user-1"}
            return {
                "success": True,
                "data": {"id": "note-grounded", "title": "Grounded note"},
            }

    gateway = AIProviderGateway(
        settings,
        google_client_factory=lambda **_kwargs: FakeGoogleClient(),
    )
    monkeypatch.setattr(gateway, "_get_tool_mapper", lambda: FakeToolMapper())
    events = [
        event
        async for event in gateway.stream_chat_with_tools(
            message="Search the web and save the result as a note",
            conversation_history=[],
            system_prompt=None,
            allowed_skills=["web-search", "notes"],
            tool_context={"user_id": "user-1"},
            settings_record=SimpleNamespace(ai_primary_provider="google"),
            provider_key_lookup=lambda _provider: "sk-google-test",
        )
    ]

    assert any(event["type"] == "tool_call" for event in events)
    assert any(event["type"] == "tool_result" for event in events)
    assert any(
        event["type"] == "entity_changed"
        and event["data"]["entity_type"] == "note"
        and event["data"]["change"] == "created"
        for event in events
    )
    assert any(
        event["type"] == "token" and event["content"] == "Completed" for event in events
    )
    first_config = captured_configs[0]
    assert first_config.tools
    first_tool = first_config.tools[0]
    assert getattr(first_tool, "google_search", None) is not None
    assert getattr(first_tool, "function_declarations", None)


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_executes_tools_from_candidate_parts(
    monkeypatch,
) -> None:
    class FakeModels:
        def __init__(self):
            self._responses = [
                SimpleNamespace(
                    text="",
                    function_calls=[],
                    candidates=[
                        SimpleNamespace(
                            content=SimpleNamespace(
                                parts=[
                                    SimpleNamespace(
                                        function_call=SimpleNamespace(
                                            id="google-call-2",
                                            name="create_note",
                                            args={"title": "Candidate note"},
                                        )
                                    )
                                ]
                            )
                        )
                    ],
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
            assert parameters == {"title": "Candidate note"}
            assert context == {"user_id": "user-1"}
            return {
                "success": True,
                "data": {"id": "note-3", "title": "Candidate note", "folder": "notes"},
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
    assert any(
        event["type"] == "entity_changed"
        and event["data"]["entity_type"] == "note"
        and event["data"]["change"] == "created"
        for event in events
    )
    assert any(
        event["type"] == "token" and event["content"] == "Completed" for event in events
    )


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_executes_tools_from_candidate_part_dict(
    monkeypatch,
) -> None:
    class FakeModels:
        def __init__(self):
            self._responses = [
                SimpleNamespace(
                    text="",
                    function_calls=[],
                    candidates=[
                        SimpleNamespace(
                            content=SimpleNamespace(
                                parts=[
                                    {
                                        "functionCall": {
                                            "id": "google-call-3",
                                            "name": "create_note",
                                            "arguments": {"title": "Dict candidate note"},
                                        }
                                    }
                                ]
                            )
                        )
                    ],
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
            assert parameters == {"title": "Dict candidate note"}
            assert context == {"user_id": "user-1"}
            return {
                "success": True,
                "data": {
                    "id": "note-4",
                    "title": "Dict candidate note",
                    "folder": "notes",
                },
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
    assert any(
        event["type"] == "entity_changed"
        and event["data"]["entity_type"] == "note"
        and event["data"]["change"] == "created"
        for event in events
    )
    assert any(
        event["type"] == "token" and event["content"] == "Completed" for event in events
    )


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_emits_error_for_empty_response(
    monkeypatch,
) -> None:
    class FakeModels:
        def generate_content(self, **_kwargs):
            return SimpleNamespace(
                text="",
                function_calls=[],
                candidates=[SimpleNamespace(finish_reason="SAFETY")],
                prompt_feedback=SimpleNamespace(block_reason="SAFETY"),
            )

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
            message="Test",
            conversation_history=[],
            system_prompt=None,
            allowed_skills=None,
            tool_context=None,
            settings_record=SimpleNamespace(ai_primary_provider="google"),
            provider_key_lookup=lambda _provider: "sk-google-test",
        )
    ]

    assert len(events) == 1
    assert events[0]["type"] == "error"
    assert events[0]["version"] == 2
    assert events[0]["category"] == "empty_response"
    assert events[0]["retryable"] is True
    assert events[0]["user_action_required"] is False
    assert events[0]["error_details"]["category"] == "empty_response"
    assert events[0]["error_details"]["provider"] == "google"
    assert events[0]["error_details"]["retryable"] is True
    assert events[0]["assistant_context"] == events[0]["error_details"]
    assert events[0]["error"] == "The AI provider returned an empty response. Please try again."
    assert events[0]["assistant_explanation"] == (
        "I couldn't complete this response because Google returned an empty response. "
        "Please try again."
    )
    assert "prompt_block_reason=SAFETY" in events[0]["error_details"]["message"]
    assert "finish_reason=SAFETY" in events[0]["error_details"]["message"]


@pytest.mark.asyncio
async def test_gateway_stream_chat_google_retries_without_tools_on_empty_response(
    monkeypatch,
) -> None:
    captured_configs: list[Any] = []

    class FakeModels:
        def __init__(self):
            self._responses = [
                SimpleNamespace(text="", function_calls=[], candidates=[]),
                SimpleNamespace(text="Recovered reply", function_calls=[], candidates=[]),
            ]

        def generate_content(self, **kwargs):
            captured_configs.append(kwargs.get("config"))
            return self._responses.pop(0)

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
            message="Test",
            conversation_history=[],
            system_prompt="Short answer",
            allowed_skills=None,
            tool_context=None,
            settings_record=SimpleNamespace(ai_primary_provider="google"),
            provider_key_lookup=lambda _provider: "sk-google-test",
        )
    ]

    assert events == [{"type": "token", "content": "Recovered reply"}]
    assert len(captured_configs) == 2
    assert getattr(captured_configs[0], "tools", None)
    assert getattr(captured_configs[1], "tools", None) == []


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
