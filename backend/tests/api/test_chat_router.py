import json
import logging
from types import SimpleNamespace

from api.config import settings
from api.db.dependencies import get_current_user_id
from api.main import app
from api.routers import chat as chat_router
from api.services.ai.gateway import ChatResolution
from api.services.conversation_service import ConversationService


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


class FakeClaudeClient:
    def __init__(self, *_args, **_kwargs):
        pass

    async def stream_with_tools(self, *_args, **_kwargs):
        yield {"type": "token", "content": "Hello"}


def test_stream_chat_emits_token_and_complete(test_client, monkeypatch):
    monkeypatch.setattr(chat_router, "ClaudeClient", FakeClaudeClient)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: token" in body
    assert json.dumps({"type": "token", "content": "Hello"}) in body
    assert "event: complete" in body


def test_stream_chat_forwards_memory_events(test_client, monkeypatch):
    class FakeMemoryClaudeClient:
        def __init__(self, *_args, **_kwargs):
            pass

        async def stream_with_tools(self, *_args, **_kwargs):
            yield {"type": "memory_created", "data": {"id": "memory-1"}}

    monkeypatch.setattr(chat_router, "ClaudeClient", FakeMemoryClaudeClient)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: memory_created" in body
    assert 'data: {"id": "memory-1"}' in body
    assert "event: complete" in body


def test_stream_chat_forwards_assistant_identity_events(test_client, monkeypatch):
    class FakeAssistantIdentityClaudeClient:
        def __init__(self, *_args, **_kwargs):
            pass

        async def stream_with_tools(self, *_args, **_kwargs):
            yield {
                "type": "assistant_identity_updated",
                "data": {
                    "assistant_identity": {"name": "Navigator"},
                    "assistant_identity_meta": {
                        "updated_at": "2026-02-18T00:00:00Z",
                        "version": 2,
                    },
                },
            }

    monkeypatch.setattr(chat_router, "ClaudeClient", FakeAssistantIdentityClaudeClient)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: assistant_identity_updated" in body
    assert '"assistant_identity": {"name": "Navigator"}' in body
    assert "event: complete" in body


def test_stream_chat_forwards_other_preferences_events(test_client, monkeypatch):
    class FakeOtherPreferencesClaudeClient:
        def __init__(self, *_args, **_kwargs):
            pass

        async def stream_with_tools(self, *_args, **_kwargs):
            yield {
                "type": "other_preferences_updated",
                "data": {
                    "weather_unit": "fahrenheit",
                    "biometric_unlock_enabled": True,
                },
            }

    monkeypatch.setattr(chat_router, "ClaudeClient", FakeOtherPreferencesClaudeClient)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: other_preferences_updated" in body
    assert '"weather_unit": "fahrenheit"' in body
    assert '"biometric_unlock_enabled": true' in body
    assert "event: complete" in body


def test_stream_chat_uses_settings_service_resolved_skills(test_client, monkeypatch):
    captured: dict[str, object] = {}

    def fake_resolve_enabled_skills(settings_record):
        captured["settings_record"] = settings_record
        return ["notes", "assistant-identity"]

    class FakeSkillAwareClaudeClient:
        def __init__(self, *_args, **_kwargs):
            pass

        async def stream_with_tools(self, *_args, **kwargs):
            captured["allowed_skills"] = kwargs.get("allowed_skills")
            yield {"type": "token", "content": "Hello"}

    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(fake_resolve_enabled_skills),
    )
    monkeypatch.setattr(chat_router, "ClaudeClient", FakeSkillAwareClaudeClient)

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200
    assert captured["settings_record"] is None
    assert captured["allowed_skills"] == ["notes", "assistant-identity"]


def test_generate_title_logs_failure(test_client, test_db, monkeypatch, caplog):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db, user_id, "Test Chat"
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {"role": "user", "content": "Hello there"},
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {"role": "assistant", "content": "Howdy"},
    )

    class FakeGeminiClient:
        def __init__(self, *_args, **_kwargs):
            self.models = self

        def generate_content(self, *_args, **_kwargs):
            raise ValueError("boom")

    monkeypatch.setattr(
        chat_router.genai, "Client", lambda *_args, **_kwargs: FakeGeminiClient()
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    caplog.set_level(logging.WARNING, logger=chat_router.logger.name)
    try:
        response = test_client.post(
            "/api/chat/generate-title",
            headers=_auth_headers(),
            json={"conversation_id": str(conversation.id)},
        )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    assert response.status_code == 200
    body = response.json()
    assert body["fallback"] is True
    assert body["title"].startswith("Hello")
    assert any(
        "Title generation failed, using fallback" in record.message
        for record in caplog.records
    )


def test_stream_chat_persists_conversation_provider_model(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db,
        user_id,
        "Provider Lock Test",
    )

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
                used_byok=False,
                used_managed_fallback=False,
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Hello"}

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda _settings_record: []),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        with test_client.stream(
            "POST",
            "/api/chat/stream",
            headers=_auth_headers(),
            json={"message": "Hi", "conversation_id": str(conversation.id)},
        ) as response:
            assert response.status_code == 200
            list(response.iter_text())
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    test_db.expire_all()
    updated = ConversationService.get_conversation(test_db, user_id, conversation.id)
    assert updated.ai_provider == "anthropic"
    assert updated.ai_model == "claude-sonnet-4-6"


def test_generate_title_uses_conversation_provider_lock(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db, user_id, "Conversation Lock"
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {"role": "user", "content": "Hello there"},
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {"role": "assistant", "content": "Howdy"},
    )
    ConversationService.set_ai_provider_model(
        test_db,
        user_id,
        conversation.id,
        provider="openai",
        model="gpt-5.2",
    )

    captured: dict[str, str | None] = {"preferred_provider": None}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        async def generate_title(self, **kwargs):
            captured["preferred_provider"] = kwargs.get("preferred_provider")
            return SimpleNamespace(raw_title="Locked Provider Title")

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: None),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/generate-title",
            headers=_auth_headers(),
            json={"conversation_id": str(conversation.id)},
        )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    assert response.status_code == 200
    assert captured["preferred_provider"] == "openai"
    assert response.json()["title"] == "Locked Provider Title"
