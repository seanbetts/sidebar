import inspect
import json
import logging
import os
import uuid
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest

from api.config import settings
from api.db import session as db_session
from api.db.dependencies import get_current_user_id
from api.main import app
from api.middleware import rate_limit as rate_limit_module
from api.routers import chat as chat_router
from api.services.ai.gateway import ChatResolution
from api.services.agent.request_assembly_service import AssembledChatInputs
from api.services.agent.request_budget_service import (
    PreparedChatRequest,
    RequestBudgetReport,
)
from api.models.conversation import Conversation
from api.services.conversation_service import ConversationService

TEST_USER_ID = os.environ["TEST_USER_ID"]


@pytest.fixture(autouse=True)
def _reset_rate_limiter():
    rate_limit_module.rate_limiter.reset()
    yield
    rate_limit_module.rate_limiter.reset()


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def _provider_settings(provider: str = "anthropic") -> SimpleNamespace:
    return SimpleNamespace(
        name=None,
        communication_style=None,
        working_relationship=None,
        enabled_skills=None,
        ai_primary_provider=provider,
    )


def _patch_stream_gateway(monkeypatch, events):
    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            for event in events:
                yield event

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)


def _sse_event_payload(body: str, event_name: str) -> dict:
    marker = f"event: {event_name}\ndata: "
    start = body.index(marker) + len(marker)
    end = body.index("\n\n", start)
    return json.loads(body[start:end])


def test_stream_chat_emits_token_and_complete(test_client, monkeypatch):
    _patch_stream_gateway(monkeypatch, [{"type": "token", "content": "Hello"}])
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
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


def test_stream_chat_normalizes_error_event_payload(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [{"type": "error", "error": "rate_limit_error: rate limit reached"}],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )

    assert response.status_code == 200
    payload = _sse_event_payload(response.text, "error")
    assert payload["type"] == "error"
    assert payload["version"] == 2
    assert payload["category"] == "provider_rate_limited"
    assert payload["retryable"] is True
    assert payload["assistant_context"]["provider"] == "anthropic"
    assert payload["error_details"]["category"] == "provider_rate_limited"
    assert payload["error_details"]["provider"] == "anthropic"
    assert payload["error_details"]["retryable"] is True
    assert "event: complete" not in response.text


def test_stream_chat_persists_failed_turn_and_hidden_diagnostics(
    test_client,
    test_db,
    monkeypatch,
):
    conversation_id = uuid.uuid4()
    conversation = Conversation(
        id=conversation_id,
        user_id=TEST_USER_ID,
        title="Provider failure",
        messages=[],
        message_count=0,
        first_message=None,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(conversation)
    test_db.commit()
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "error",
                "error": "insufficient_quota",
                "category": "provider_billing",
            }
        ],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={
            "message": "Hi",
            "conversation_id": str(conversation_id),
            "user_message_id": "user-1",
            "assistant_message_id": "assistant-1",
        },
    )

    assert response.status_code == 200
    test_db.refresh(conversation)
    assert conversation.message_count == 2
    assert [message["id"] for message in conversation.messages] == [
        "user-1",
        "assistant-1",
        "diag-assistant-1",
    ]
    assert conversation.messages[1]["status"] == "error"
    assert (
        conversation.messages[1]["error"]
        == "The AI provider account needs billing attention."
    )
    assert conversation.messages[1]["content"].startswith(
        "I couldn't complete this response"
    )
    assert conversation.messages[1].get("errorDetails") is None
    assert conversation.messages[2]["visibility"] == "hidden"
    assert conversation.messages[2]["kind"] == "assistant_error_diagnostics"
    assert conversation.messages[2]["related_message_id"] == "assistant-1"
    assert conversation.messages[2]["diagnostics"]["category"] == "provider_billing"


def test_stream_chat_route_has_no_db_dependency():
    parameters = inspect.signature(chat_router.stream_chat).parameters

    assert "db" not in parameters


def test_stream_chat_does_not_hold_request_scoped_db_for_stream_lifetime(
    test_client, monkeypatch
):
    class RequestScopedSession:
        def __init__(self) -> None:
            self.closed = False
            self.info: dict[str, object] = {}

        def close(self) -> None:
            self.closed = True

    class StreamScopedSession:
        def __init__(self) -> None:
            self.closed = False
            self.info: dict[str, object] = {}

        def close(self) -> None:
            self.closed = True

    observed: dict[str, object] = {
        "request_db_calls": 0,
        "request_db_closed_at_stream_start": None,
        "tool_context_db_is_request_db": None,
        "provider_lookup_db_is_request_db": None,
    }
    request_db = RequestScopedSession()
    stream_sessions: list[StreamScopedSession] = []

    def fake_get_db():
        observed["request_db_calls"] += 1
        try:
            yield request_db
        finally:
            request_db.close()

    def fake_session_local():
        session = StreamScopedSession()
        stream_sessions.append(session)
        return session

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(
            self,
            *,
            tool_context,
            provider_key_lookup,
            **_kwargs,
        ):
            observed["request_db_closed_at_stream_start"] = request_db.closed
            observed["tool_context_db_is_request_db"] = (
                getattr(tool_context, "db", None) is request_db
            )
            provider_key_lookup("anthropic")
            yield {"type": "token", "content": "Hello"}

    def fake_get_active_key(db, _user_id, _provider):
        observed["provider_lookup_db_is_request_db"] = db is request_db
        return "stream-key"

    def _build_assembled_inputs(**_kwargs):
        return AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Hi",
            prompt_bundle={},
        )

    def _build_prepared_request(**_kwargs):
        return PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Hi",
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=40000,
                reserved_output_chars=4000,
                available_input_chars=35000,
                provider_framing_chars=100,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=0,
                current_message_chars=2,
                tool_schema_chars=0,
                total_input_chars=8,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(db_session, "SessionLocal", fake_session_local)
    monkeypatch.setattr(
        db_session, "set_session_user_id", lambda *_args, **_kwargs: None
    )
    monkeypatch.setattr(
        chat_router.UserAIProviderKeyService,
        "get_active_key",
        staticmethod(fake_get_active_key),
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.OnboardingService,
        "get_onboarding_state",
        staticmethod(lambda *_args, **_kwargs: None),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )
    monkeypatch.setattr(
        chat_router.SkillCatalogService,
        "list_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )
    monkeypatch.setattr(
        chat_router.RuntimeCapabilityService,
        "list_runtime_states",
        staticmethod(lambda *_args, **_kwargs: []),
    )
    monkeypatch.setattr(
        chat_router.CapabilityResolverService,
        "resolve_for_turn",
        staticmethod(
            lambda **_kwargs: {
                "selected_skill_ids": [],
                "executable_skill_ids": [],
                "blocked_skill_summaries": [],
            }
        ),
    )
    monkeypatch.setattr(
        chat_router.CapabilityLoaderService,
        "load_for_turn",
        staticmethod(lambda **_kwargs: {}),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(_build_assembled_inputs),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )
    app.dependency_overrides[db_session.get_db] = fake_get_db

    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={"message": "Hi"},
        )
    finally:
        app.dependency_overrides.pop(db_session.get_db, None)

    assert response.status_code == 200
    assert observed["request_db_calls"] == 0 or (
        observed["request_db_closed_at_stream_start"] is True
    )
    assert observed["tool_context_db_is_request_db"] is False
    assert observed["provider_lookup_db_is_request_db"] is False
    assert stream_sessions
    assert all(session.closed for session in stream_sessions)
    assert "event: token" in response.text
    assert "event: complete" in response.text


def test_stream_chat_rate_limit_is_user_scoped(test_client, monkeypatch):
    _patch_stream_gateway(monkeypatch, [{"type": "token", "content": "Hello"}])
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setitem(
        rate_limit_module.RATE_LIMIT_POLICIES,
        "chat_stream",
        rate_limit_module.RateLimitPolicy(limit=1, window_seconds=60),
    )
    rate_limit_module.rate_limiter.reset()

    app.dependency_overrides[get_current_user_id] = lambda: "rate-user-1"
    try:
        first = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={"message": "Hi"},
        )
        second = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={"message": "Hi again"},
        )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    app.dependency_overrides[get_current_user_id] = lambda: "rate-user-2"
    try:
        third = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={"message": "Hi from another user"},
        )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        rate_limit_module.rate_limiter.reset()

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.headers["Retry-After"]
    payload = second.json()
    assert payload["error"]["code"] == "RATE_LIMITED"
    assert payload["error"]["details"]["scope"] == "chat_stream"
    assert third.status_code == 200


def test_stream_chat_forwards_memory_invalidated_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [{"type": "collection_invalidated", "data": {"targets": ["memory"]}}],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: collection_invalidated" in body
    assert '"targets": ["memory"]' in body
    assert "event: complete" in body


def test_stream_chat_forwards_assistant_settings_invalidated_events(
    test_client, monkeypatch
):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "collection_invalidated",
                "data": {"targets": ["assistant_settings"]},
            }
        ],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: collection_invalidated" in body
    assert '"targets": ["assistant_settings"]' in body
    assert "event: complete" in body


def test_stream_chat_loads_onboarding_state_and_passes_it_to_request_assembly(
    test_client, monkeypatch
):
    captured: dict[str, object] = {}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Hello"}

    onboarding_state = {
        "status": "dismissed",
        "provider_ready": False,
        "current_onboarding_step": "provider_recovery",
        "is_onboarding_complete": False,
        "intent": "notes",
        "milestones": {},
        "permissions": {"location": "not_asked", "notifications": "not_asked"},
        "last_prompted_at": None,
    }

    def _build_assembled_inputs(**kwargs):
        captured["onboarding_state"] = kwargs.get("onboarding_state")
        return AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Help me finish setup",
            prompt_bundle={},
        )

    def _build_prepared_request(**_kwargs):
        return PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Help me finish setup",
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=40000,
                reserved_output_chars=4000,
                available_input_chars=35000,
                provider_framing_chars=100,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=0,
                current_message_chars=20,
                tool_schema_chars=0,
                total_input_chars=26,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.OnboardingService,
        "get_onboarding_state",
        staticmethod(lambda *_args, **_kwargs: onboarding_state),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(_build_assembled_inputs),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200
    assert captured["onboarding_state"] == onboarding_state


def test_stream_chat_passes_onboarding_state_to_capability_resolver(
    test_client, monkeypatch
):
    captured: dict[str, object] = {}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Hello"}

    onboarding_state = {
        "status": "dismissed",
        "provider_ready": False,
        "current_onboarding_step": "provider_recovery",
        "is_onboarding_complete": False,
        "intent": "notes",
        "milestones": {},
        "permissions": {"location": "not_asked", "notifications": "not_asked"},
        "last_prompted_at": None,
    }

    class FakeResolverService:
        @staticmethod
        def resolve_for_turn(**kwargs):
            captured["resolver_onboarding_state"] = kwargs.get("onboarding_state")
            return {
                "selected_skill_ids": ["onboarding-coach"],
                "executable_skill_ids": ["onboarding-coach"],
                "blocked_skill_summaries": [],
            }

    def _build_assembled_inputs(**_kwargs):
        return AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Help me finish setup",
            prompt_bundle={},
        )

    def _build_prepared_request(**_kwargs):
        return PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Help me finish setup",
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=40000,
                reserved_output_chars=4000,
                available_input_chars=35000,
                provider_framing_chars=100,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=0,
                current_message_chars=20,
                tool_schema_chars=0,
                total_input_chars=26,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.OnboardingService,
        "get_onboarding_state",
        staticmethod(lambda *_args, **_kwargs: onboarding_state),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(_build_assembled_inputs),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )
    monkeypatch.setattr(chat_router, "CapabilityResolverService", FakeResolverService)

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Help me finish setup"},
    )
    assert response.status_code == 200
    assert captured["resolver_onboarding_state"] == onboarding_state


def test_stream_chat_blocks_provider_ready_users_until_soul_calibration_completes(
    test_client, monkeypatch
):
    onboarding_state = {
        "status": "in_progress",
        "provider_ready": True,
        "current_onboarding_step": "soul_calibration",
        "is_onboarding_complete": False,
        "intent": "notes",
        "milestones": {},
        "permissions": {"location": "not_asked", "notifications": "not_asked"},
        "last_prompted_at": None,
        "calibration": {
            "status": "in_progress",
            "current_prompt": "working_relationship",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": None,
                "tone_preferences": None,
            },
            "proposed_name": None,
            "completed_at": None,
        },
    }

    class BlockedGateway:
        def __init__(self, *_args, **_kwargs):
            pytest.fail("AI gateway should not be initialized during soul calibration")

    monkeypatch.setattr(chat_router, "AIProviderGateway", BlockedGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.OnboardingService,
        "get_onboarding_state",
        staticmethod(lambda *_args, **_kwargs: onboarding_state),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )

    assert response.status_code == 409
    assert response.json() == {
        "error": {
            "code": "ONBOARDING_REQUIRED",
            "message": "Soul calibration must complete before AI chat is available.",
            "details": {
                "onboarding_state": onboarding_state,
            },
        }
    }


def test_stream_chat_allows_provider_ready_users_after_soul_calibration(
    test_client, monkeypatch
):
    onboarding_state = {
        "status": "in_progress",
        "provider_ready": True,
        "current_onboarding_step": "feature_discovery",
        "is_onboarding_complete": False,
        "intent": "notes",
        "milestones": {"provider_connected": "2026-04-02T09:00:00Z"},
        "permissions": {"location": "not_asked", "notifications": "not_asked"},
        "last_prompted_at": None,
        "calibration": {
            "status": "completed",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "coach",
                "tone_preferences": "warm,direct",
            },
            "proposed_name": "Navigator",
            "completed_at": "2026-04-02T09:10:00Z",
        },
    }

    _patch_stream_gateway(monkeypatch, [{"type": "token", "content": "Hello"}])
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.OnboardingService,
        "get_onboarding_state",
        staticmethod(lambda *_args, **_kwargs: onboarding_state),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )

    assert response.status_code == 200
    assert "event: token" in response.text


def test_stream_chat_forwards_preferences_invalidated_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "collection_invalidated",
                "data": {"targets": ["preferences"]},
            }
        ],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: collection_invalidated" in body
    assert '"targets": ["preferences"]' in body
    assert "event: complete" in body


def test_stream_chat_forwards_workspace_patch_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "workspace_patch",
                "data": {
                    "version": 1,
                    "operations": [{"op": "swap_panes"}],
                },
            }
        ],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: workspace_patch" in body
    assert '"version": 1' in body
    assert '"op": "swap_panes"' in body
    assert "event: complete" in body


def test_stream_chat_forwards_onboarding_stream_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "onboarding_provider_blocked",
                "data": {
                    "current_onboarding_step": "provider_recovery",
                    "provider_ready": False,
                },
            },
            {
                "type": "onboarding_resume_suggested",
                "data": {
                    "current_onboarding_step": "feature_discovery",
                    "provider_ready": True,
                },
            },
            {
                "type": "onboarding_milestone_completed",
                "data": {
                    "current_onboarding_step": "feature_discovery",
                    "provider_ready": True,
                    "milestone": "provider_connected",
                },
            },
        ],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: onboarding_provider_blocked" in body
    assert "event: onboarding_resume_suggested" in body
    assert "event: onboarding_milestone_completed" in body
    assert '"milestone": "provider_connected"' in body


def test_stream_chat_forwards_conversation_entity_changed_events(
    test_client, monkeypatch
):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "entity_changed",
                "data": {
                    "entity_type": "conversation",
                    "entity_id": "conv-1",
                    "change": "renamed",
                    "patch": {
                        "title": "Renamed",
                        "titleGenerated": False,
                        "updatedAt": "2026-03-28T12:00:00Z",
                    },
                    "invalidate": ["conversations", "conversation:conv-1"],
                },
            }
        ],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: entity_changed" in body
    assert '"entity_type": "conversation"' in body
    assert '"title": "Renamed"' in body
    assert '"invalidate": ["conversations", "conversation:conv-1"]' in body
    assert '"change": "renamed"' in body
    assert "event: complete" in body


def test_stream_chat_forwards_tool_status_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "tool_status",
                "data": {
                    "tool_call_id": "tool-1",
                    "status": "completed",
                    "display_name": "Rename Website",
                    "summary": "Renamed website to New Name",
                },
            }
        ],
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: tool_status" in body
    assert '"tool_call_id": "tool-1"' in body
    assert '"status": "completed"' in body
    assert "event: complete" in body


def test_stream_chat_uses_settings_service_resolved_skills(test_client, monkeypatch):
    captured: dict[str, object] = {}

    def fake_resolve_enabled_skills(settings_record, *args, **kwargs):
        captured["settings_record"] = settings_record
        return ["notes", "assistant-identity"]

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["allowed_skills"] = kwargs.get("allowed_skills")
            yield {"type": "token", "content": "Hello"}

    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(fake_resolve_enabled_skills),
    )
    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200
    assert captured["settings_record"] is not None
    assert captured["allowed_skills"] == ["notes", "assistant-identity"]


def test_stream_chat_keeps_blocked_skills_visible_but_only_executes_executable_subset(
    test_client, monkeypatch
):
    captured: dict[str, object] = {}

    class FakeResolverService:
        @staticmethod
        def resolve_for_turn(**kwargs):
            captured["resolver_enabled_skill_ids"] = kwargs.get("enabled_skill_ids")
            return {
                "selected_skill_ids": ["notes", "google-drive"],
                "executable_skill_ids": ["notes"],
                "blocked_skill_summaries": [
                    {
                        "skill_id": "google-drive",
                        "availability_status": "needs_connection",
                        "availability_reason": "missing_connection",
                        "availability_remediation": {
                            "action": "connect",
                            "provider": "google-workspace",
                        },
                    }
                ],
            }

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["allowed_skills"] = kwargs.get("allowed_skills")
            yield {"type": "token", "content": "Hello"}

    def _build_assembled_inputs(**kwargs):
        captured["blocked_skill_summaries"] = kwargs.get("blocked_skill_summaries")
        return AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Help me connect Google Drive",
            prompt_bundle={},
        )

    def _build_prepared_request(**kwargs):
        captured["executable_skill_ids"] = kwargs.get("executable_skill_ids")
        return PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Help me connect Google Drive",
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=40000,
                reserved_output_chars=4000,
                available_input_chars=35000,
                provider_framing_chars=100,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=0,
                current_message_chars=28,
                tool_schema_chars=0,
                total_input_chars=34,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: ["notes", "google-drive"]),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(_build_assembled_inputs),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )
    monkeypatch.setattr(
        chat_router,
        "CapabilityResolverService",
        FakeResolverService,
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Help me connect Google Drive"},
    )
    assert response.status_code == 200
    assert captured["resolver_enabled_skill_ids"] == ["notes", "google-drive"]
    assert captured["blocked_skill_summaries"] == [
        {
            "skill_id": "google-drive",
            "availability_status": "needs_connection",
            "availability_reason": "missing_connection",
            "availability_remediation": {
                "action": "connect",
                "provider": "google-workspace",
            },
        }
    ]
    assert captured["executable_skill_ids"] == ["notes"]
    assert captured["allowed_skills"] == ["notes"]


def test_stream_chat_downgrades_unsupported_openai_web_search_with_provider_specific_remediation(
    test_client, monkeypatch
):
    captured: dict[str, object] = {}

    class FakeResolverService:
        @staticmethod
        def resolve_for_turn(**kwargs):
            captured["resolver_enabled_skill_ids"] = kwargs.get("enabled_skill_ids")
            return {
                "selected_skill_ids": ["web-search", "notes"],
                "executable_skill_ids": ["web-search", "notes"],
                "blocked_skill_summaries": [],
            }

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def get_chat_tool_definitions(self, allowed_skills=None):
            captured["tool_definition_allowed_skills"] = allowed_skills
            return []

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="openai",
                model="gpt-4o-mini",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["allowed_skills"] = kwargs.get("allowed_skills")
            yield {"type": "token", "content": "Hello"}

    def _build_assembled_inputs(**kwargs):
        captured["blocked_skill_summaries"] = kwargs.get("blocked_skill_summaries")
        return AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Search the web and save a note",
            prompt_bundle={},
        )

    def _build_prepared_request(**kwargs):
        captured["prepared_executable_skill_ids"] = kwargs.get("executable_skill_ids")
        captured["prepared_provider"] = kwargs.get("provider")
        captured["prepared_model"] = kwargs.get("model")
        return PreparedChatRequest(
            provider="openai",
            model="gpt-4o-mini",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Search the web and save a note",
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="openai",
                model="gpt-4o-mini",
                context_window_chars=40000,
                reserved_output_chars=4000,
                available_input_chars=35000,
                provider_framing_chars=100,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=0,
                current_message_chars=30,
                tool_schema_chars=0,
                total_input_chars=36,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings("openai")),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: ["web-search", "notes"]),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(_build_assembled_inputs),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )
    monkeypatch.setattr(
        chat_router,
        "CapabilityResolverService",
        FakeResolverService,
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Search the web and save a note"},
    )
    assert response.status_code == 200
    assert captured["prepared_executable_skill_ids"] == ["notes"]
    assert captured["allowed_skills"] == ["notes"]
    assert captured["blocked_skill_summaries"] == [
        {
            "skill_id": "web-search",
            "availability_status": "provider_model_unsupported",
            "availability_reason": (
                "Web Search is unavailable for OpenAI model 'gpt-4o-mini'. "
                "sideBar will continue without web search. Switch to a GPT-5 "
                "or GPT-4.1 model to enable it."
            ),
            "availability_remediation": {
                "action": "switch_model",
                "provider": "openai",
            },
        }
    ]


def test_stream_chat_passes_prepared_tool_definitions_to_gateway_execution(
    test_client, monkeypatch
):
    captured: dict[str, object] = {}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["tool_definitions"] = kwargs.get("tool_definitions")
            captured["allowed_skills"] = kwargs.get("allowed_skills")
            yield {"type": "token", "content": "Hello"}

    def _build_assembled_inputs(**_kwargs):
        return AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Summarize my notes",
            prompt_bundle={},
        )

    def _build_prepared_request(**_kwargs):
        return PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[],
            current_user_message="Summarize my notes",
            tool_definitions=[
                {
                    "name": "lookup_note",
                    "description": "Open a note by ID.",
                    "input_schema": {
                        "type": "object",
                        "properties": {"note_id": {"type": "string"}},
                        "required": ["note_id"],
                    },
                }
            ],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=40000,
                reserved_output_chars=4000,
                available_input_chars=35000,
                provider_framing_chars=100,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=0,
                current_message_chars=18,
                tool_schema_chars=120,
                total_input_chars=144,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: ["notes"]),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(_build_assembled_inputs),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Summarize my notes"},
    )

    assert response.status_code == 200
    assert captured["allowed_skills"] == ["notes"]
    assert captured["tool_definitions"] == [
        {
            "name": "lookup_note",
            "description": "Open a note by ID.",
            "input_schema": {
                "type": "object",
                "properties": {"note_id": {"type": "string"}},
                "required": ["note_id"],
            },
        }
    ]


def test_stream_chat_passes_app_version_to_tool_context(test_client, monkeypatch):
    captured: dict[str, object] = {}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["tool_context"] = kwargs.get("tool_context")
            yield {"type": "token", "content": "Hello"}

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers={**_auth_headers(), "X-App-Version": "1.4.2"},
        json={"message": "Hi"},
    )
    assert response.status_code == 200
    context = captured["tool_context"]
    assert context is not None
    assert getattr(context, "app_version", None) == "1.4.2"


def test_stream_chat_passes_prompt_preview_payload_to_tool_context(
    test_client, monkeypatch
):
    captured: dict[str, object] = {}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["tool_context"] = kwargs.get("tool_context")
            yield {"type": "token", "content": "Hello"}

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200
    context = captured["tool_context"]
    assert context is not None
    prompt_preview_payload = getattr(context, "prompt_preview_payload", None)
    assert prompt_preview_payload is not None
    assert prompt_preview_payload["request_budget_report"]["current_message_chars"] == 2
    assert prompt_preview_payload["request_budget_report"]["tool_schema_chars"] > 0


def test_stream_chat_injects_bootstrap_history_on_first_turn(test_client, monkeypatch):
    captured: dict[str, object] = {}

    def _build_prompts(**_kwargs):
        return {
            "system_prompt": {
                "text": "system",
                "max_chars": 40000,
                "total_chars": 6,
                "raw_total_chars": 6,
                "constrained_total_chars": 6,
                "truncated": False,
                "truncated_by_section_limits": False,
                "truncated_by_budget": False,
                "sections": [],
            },
            "first_message_prompt": {
                "text": "I am Sam.",
                "max_chars": 8000,
                "total_chars": 9,
                "raw_total_chars": 9,
                "constrained_total_chars": 9,
                "truncated": False,
                "truncated_by_section_limits": False,
                "truncated_by_budget": False,
                "sections": [],
            },
            "report": {
                "system_prompt": {
                    "total_chars": 6,
                    "max_chars": 40000,
                    "raw_total_chars": 6,
                    "constrained_total_chars": 6,
                    "truncated": False,
                    "truncated_by_section_limits": False,
                    "truncated_by_budget": False,
                    "sections": [],
                },
                "first_message_prompt": {
                    "total_chars": 9,
                    "max_chars": 8000,
                    "raw_total_chars": 9,
                    "constrained_total_chars": 9,
                    "truncated": False,
                    "truncated_by_section_limits": False,
                    "truncated_by_budget": False,
                    "sections": [],
                },
            },
        }

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["conversation_history"] = kwargs.get("conversation_history")
            yield {"type": "token", "content": "Hello"}

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.PromptContextService,
        "build_prompts",
        staticmethod(_build_prompts),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200
    assert captured["conversation_history"] == [
        {"role": "user", "content": "I am Sam."}
    ]


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
        staticmethod(lambda *_args, **_kwargs: _provider_settings("google")),
    )
    monkeypatch.setattr(
        chat_router.UserAIProviderKeyService,
        "get_active_key",
        staticmethod(lambda *_args, **_kwargs: "google-test-key"),
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
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Hello"}

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={"message": "Hi", "conversation_id": str(conversation.id)},
        )
        assert response.status_code == 200
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    test_db.expire_all()
    updated = ConversationService.get_conversation(test_db, user_id, conversation.id)
    assert updated.ai_provider == "anthropic"
    assert updated.ai_model == "claude-sonnet-4-6"


def test_stream_chat_persists_turn_pair_atomically(test_client, test_db, monkeypatch):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db,
        user_id,
        "Turn Pair Test",
    )

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Hello"}
            yield {
                "type": "tool_call",
                "id": "tool-1",
                "name": "Create Note",
                "parameters": {"title": "From test"},
                "status": "pending",
            }
            yield {
                "type": "tool_result",
                "id": "tool-1",
                "name": "Create Note",
                "result": {"success": True, "data": {"id": "note-1"}},
                "status": "success",
            }

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={
                "message": "Hi",
                "conversation_id": str(conversation.id),
                "user_message_id": "user-msg-1",
                "assistant_message_id": "assistant-msg-1",
            },
        )
        assert response.status_code == 200
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    test_db.expire_all()
    updated = ConversationService.get_conversation(test_db, user_id, conversation.id)
    assert updated.message_count == 2
    assert len(updated.messages) == 3
    assert updated.messages[0]["role"] == "user"
    assert updated.messages[0]["visibility"] == "hidden"
    assert updated.messages[0]["kind"] == "conversation_bootstrap"
    assert updated.messages[1]["id"] == "user-msg-1"
    assert updated.messages[1]["role"] == "user"
    assert updated.messages[1]["content"] == "Hi"
    assert updated.messages[2]["id"] == "assistant-msg-1"
    assert updated.messages[2]["role"] == "assistant"
    assert updated.messages[2]["content"] == "Hello"
    assert updated.messages[2]["toolCalls"][0]["id"] == "tool-1"
    assert updated.messages[2]["toolCalls"][0]["status"] == "success"


def test_stream_chat_rejects_oversized_system_prompt(test_client, monkeypatch):
    def _raise_prompt_size_error(**_kwargs):
        raise ValueError("too large")

    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.PromptContextService,
        "build_prompts",
        staticmethod(_raise_prompt_size_error),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 400


def test_stream_chat_persists_hidden_user_instruction_without_visible_count(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db, user_id, "Hidden Kickoff"
    )

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Hi, I'm Voss."}

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={
                "message": "Introduce yourself and mention the Explore sideBar pill.",
                "conversation_id": str(conversation.id),
                "assistant_message_id": "assistant-msg-1",
                "message_visibility": "hidden",
            },
        )
        assert response.status_code == 200
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    test_db.expire_all()
    updated = ConversationService.get_conversation(test_db, user_id, conversation.id)
    assert updated.message_count == 1
    assert len(updated.messages) == 3
    assert updated.messages[0]["kind"] == "conversation_bootstrap"
    assert updated.messages[0]["visibility"] == "hidden"
    assert updated.messages[1]["role"] == "user"
    assert updated.messages[1]["visibility"] == "hidden"
    assert updated.messages[2]["role"] == "assistant"
    assert updated.messages[2]["content"] == "Hi, I'm Voss."


def test_stream_chat_persists_synthetic_tool_newline_after_completed_tool_status(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db, user_id, "Tool Boundary Persistence"
    )

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {
                "type": "token",
                "content": "The checklist `list_item` blocks need a `checked` boolean field. Let me fix that.",
            }
            yield {
                "type": "tool_call",
                "id": "tool-1",
                "name": "Create Note",
                "parameters": {"title": "Test Note: Cosmic Observations"},
                "status": "pending",
            }
            yield {
                "type": "tool_result",
                "id": "tool-1",
                "name": "Create Note",
                "result": {"success": True, "data": {"id": "note-1"}},
                "status": "success",
            }
            yield {
                "type": "tool_status",
                "data": {
                    "tool_call_id": "tool-1",
                    "status": "success",
                    "display_name": "Create Note",
                },
            }
            yield {
                "type": "token",
                "content": 'Done — **"Test Note: Cosmic Observations"** is now in your notes.',
            }

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={
                "message": "Create a note and tell me when it's done",
                "conversation_id": str(conversation.id),
                "assistant_message_id": "assistant-msg-1",
            },
        )
        assert response.status_code == 200
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    test_db.expire_all()
    updated = ConversationService.get_conversation(test_db, user_id, conversation.id)
    assert updated.messages[2]["id"] == "assistant-msg-1"
    assert updated.messages[2]["content"] == (
        "The checklist `list_item` blocks need a `checked` boolean field. Let me fix that.\n\n"
        'Done — **"Test Note: Cosmic Observations"** is now in your notes.'
    )


def test_stream_chat_emits_assistant_reply_notification_when_user_is_away(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db,
        user_id,
        "Assistant Reply Notification",
    )
    captured: dict[str, object] = {}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Done."}

    class FakeDeviceTokenService:
        @staticmethod
        def list_active_tokens(_db, _user_id, **_kwargs):
            captured["listed_tokens"] = True
            return [
                SimpleNamespace(
                    token="token-1",
                    platform="ios",
                    is_foreground=False,
                    capabilities={},
                )
            ]

    class FakeNotificationPolicyService:
        @staticmethod
        def evaluate(intent, *, settings_record=None, device_tokens=None):
            captured["intent"] = intent
            captured["policy_settings"] = settings_record
            captured["policy_tokens"] = tuple(device_tokens or ())
            return SimpleNamespace(
                should_deliver=True,
                reason=None,
                matched_tokens=tuple(device_tokens or ()),
            )

    class FakeNotificationDeliveryService:
        @staticmethod
        def deliver_intent(intent, *, device_tokens=None):
            captured["delivered_intent"] = intent
            captured["delivered_tokens"] = tuple(device_tokens or ())
            return SimpleNamespace(
                status="sent",
                request_count=len(tuple(device_tokens or ())),
                sent_count=len(tuple(device_tokens or ())),
                reason=None,
            )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router, "DeviceTokenService", FakeDeviceTokenService, raising=False
    )
    monkeypatch.setattr(
        chat_router,
        "NotificationPolicyService",
        FakeNotificationPolicyService,
        raising=False,
    )
    monkeypatch.setattr(
        chat_router,
        "NotificationDeliveryService",
        FakeNotificationDeliveryService,
        raising=False,
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(
            lambda *_args, **_kwargs: SimpleNamespace(
                name=None,
                communication_style=None,
                working_relationship=None,
                enabled_skills=None,
                ai_primary_provider="anthropic",
                notification_preferences={
                    "assistant_reply_notifications_enabled": True,
                },
            )
        ),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={"message": "Hi", "conversation_id": str(conversation.id)},
        )
        assert response.status_code == 200
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    delivered_intent = captured.get("delivered_intent")
    assert delivered_intent is not None
    assert delivered_intent.category.value == "assistant_reply"
    assert delivered_intent.route == f"sidebar://chat/{conversation.id}"
    assert delivered_intent.body == "Done."
    assert delivered_intent.metadata == {
        "conversation_id": str(conversation.id),
    }
    assert len(captured.get("delivered_tokens", ())) == 1


def test_stream_chat_skips_assistant_reply_notification_for_hidden_messages(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db,
        user_id,
        "Hidden Notification Suppression",
    )
    captured: dict[str, object] = {"delivery_calls": 0}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **_kwargs):
            yield {"type": "token", "content": "Silent update"}

    class FakeNotificationDeliveryService:
        @staticmethod
        def deliver_intent(intent, *, device_tokens=None):
            _ = intent
            _ = device_tokens
            captured["delivery_calls"] = int(captured["delivery_calls"]) + 1
            return SimpleNamespace(
                status="sent", request_count=1, sent_count=1, reason=None
            )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router,
        "NotificationDeliveryService",
        FakeNotificationDeliveryService,
        raising=False,
    )
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(
            lambda *_args, **_kwargs: SimpleNamespace(
                name=None,
                communication_style=None,
                working_relationship=None,
                enabled_skills=None,
                ai_primary_provider="anthropic",
                notification_preferences={
                    "assistant_reply_notifications_enabled": True,
                },
            )
        ),
    )
    monkeypatch.setattr(
        chat_router.SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda *_args, **_kwargs: []),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={
                "message": "Hi",
                "conversation_id": str(conversation.id),
                "message_visibility": "hidden",
            },
        )
        assert response.status_code == 200
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    assert captured["delivery_calls"] == 0


def test_stream_chat_rejects_request_that_exceeds_budget_after_trimming(
    test_client, monkeypatch
):
    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

    def _build_prepared_request(**kwargs):
        assembled_inputs = kwargs["assembled_inputs"]
        return PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt=assembled_inputs.system_prompt,
            bootstrap_history=assembled_inputs.bootstrap_history,
            conversation_history=[],
            current_user_message=assembled_inputs.current_user_message,
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=100,
                reserved_output_chars=20,
                available_input_chars=70,
                provider_framing_chars=10,
                system_prompt_chars=50,
                bootstrap_history_chars=20,
                conversation_history_chars=0,
                current_message_chars=20,
                tool_schema_chars=0,
                total_input_chars=100,
                overflow_chars=30,
                within_budget=False,
                failure_reason="request_too_large",
                trimming_applied=True,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )

    assert response.status_code == 400
    assert response.json()["error"]["message"] == (
        "Message context is too large for this chat request. Remove some attachments or close open items and try again."
    )


def test_stream_chat_compacts_trimmed_history_and_retries_prepared_request(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db,
        user_id,
        "Compaction Test",
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {
            "id": "msg-existing-1",
            "role": "user",
            "content": "Earlier question",
            "status": "complete",
            "timestamp": datetime.now(UTC).isoformat(),
        },
    )

    assembled_inputs = [
        AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[
                {"role": "user", "content": "Earlier question"},
                {"role": "assistant", "content": "Earlier answer"},
                {"role": "assistant", "content": "Recent answer"},
            ],
            current_user_message="Current question",
            prompt_bundle={},
        ),
        AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[
                {"role": "assistant", "content": "Earlier conversation summary"},
                {"role": "assistant", "content": "Recent answer"},
            ],
            current_user_message="Current question",
            prompt_bundle={},
        ),
    ]
    prepared_requests = [
        PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[
                {"role": "assistant", "content": "Recent answer"},
            ],
            current_user_message="Current question",
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=1000,
                reserved_output_chars=100,
                available_input_chars=850,
                provider_framing_chars=50,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=30,
                current_message_chars=16,
                tool_schema_chars=0,
                total_input_chars=102,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=True,
                compaction_applied=False,
            ),
        ),
        PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system",
            bootstrap_history=[],
            conversation_history=[
                {"role": "assistant", "content": "Earlier conversation summary"},
                {"role": "assistant", "content": "Recent answer"},
            ],
            current_user_message="Current question",
            tool_definitions=[],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=1000,
                reserved_output_chars=100,
                available_input_chars=850,
                provider_framing_chars=50,
                system_prompt_chars=6,
                bootstrap_history_chars=0,
                conversation_history_chars=70,
                current_message_chars=16,
                tool_schema_chars=0,
                total_input_chars=142,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=True,
            ),
        ),
    ]
    captured: dict[str, object] = {}

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        def resolve_chat(self, **_kwargs):
            return ChatResolution(
                provider="anthropic",
                model="claude-sonnet-4-6",
                api_key="test-key",
            )

        async def stream_chat_with_tools(self, **kwargs):
            captured["conversation_history"] = kwargs.get("conversation_history")
            yield {"type": "token", "content": "Hello"}

    def _build_assembled_inputs(**_kwargs):
        return assembled_inputs.pop(0)

    def _build_prepared_request(**_kwargs):
        return prepared_requests.pop(0)

    def _compact_conversation_history(**kwargs):
        captured["replay_messages_to_compact"] = kwargs["replay_messages_to_compact"]
        return ConversationService.get_conversation(
            test_db,
            user_id,
            conversation.id,
        )

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(_build_assembled_inputs),
    )
    monkeypatch.setattr(
        chat_router.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(_build_prepared_request),
    )
    monkeypatch.setattr(
        chat_router.ConversationCompactionService,
        "compact_conversation_history",
        staticmethod(_compact_conversation_history),
    )

    app.dependency_overrides[get_current_user_id] = lambda: user_id
    try:
        response = test_client.post(
            "/api/chat/stream",
            headers=_auth_headers(),
            json={
                "message": "Current question",
                "conversation_id": str(conversation.id),
            },
        )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)

    assert response.status_code == 200
    assert captured["replay_messages_to_compact"] == 2
    assert captured["conversation_history"] == [
        {"role": "assistant", "content": "Earlier conversation summary"},
        {"role": "assistant", "content": "Recent answer"},
    ]


def test_stream_chat_allows_section_capped_prompt_report(test_client, monkeypatch):
    def _build_prompts(**_kwargs):
        return {
            "system_prompt": {
                "text": "system",
                "max_chars": 40000,
                "total_chars": 14288,
                "raw_total_chars": 45500,
                "constrained_total_chars": 14288,
                "truncated": True,
                "truncated_by_section_limits": True,
                "truncated_by_budget": False,
                "sections": [],
            },
            "first_message_prompt": {
                "text": "first",
                "max_chars": 8000,
                "total_chars": 5,
                "raw_total_chars": 5,
                "constrained_total_chars": 5,
                "truncated": False,
                "truncated_by_section_limits": False,
                "truncated_by_budget": False,
                "sections": [],
            },
            "report": {
                "system_prompt": {
                    "total_chars": 14288,
                    "max_chars": 40000,
                    "raw_total_chars": 45500,
                    "constrained_total_chars": 14288,
                    "truncated": True,
                    "truncated_by_section_limits": True,
                    "truncated_by_budget": False,
                    "sections": [],
                },
                "first_message_prompt": {
                    "total_chars": 5,
                    "max_chars": 8000,
                    "raw_total_chars": 5,
                    "constrained_total_chars": 5,
                    "truncated": False,
                    "truncated_by_section_limits": False,
                    "truncated_by_budget": False,
                    "sections": [],
                },
            },
        }

    _patch_stream_gateway(monkeypatch, [{"type": "token", "content": "Hello"}])
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.PromptContextService,
        "build_prompts",
        staticmethod(_build_prompts),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )

    assert response.status_code == 200
    assert "event: token" in response.text


def test_stream_chat_retries_without_attachment_content_on_prompt_overflow(
    test_client, monkeypatch
):
    captured_flags: list[bool] = []

    def _build_prompts(**kwargs):
        include_attachment_content = kwargs.get("include_attachment_content", True)
        captured_flags.append(bool(include_attachment_content))
        if include_attachment_content:
            raise ValueError("System prompt exceeds maximum size (50001 > 40000)")
        return {
            "system_prompt": {
                "text": "system",
                "max_chars": 40000,
                "total_chars": 6,
                "truncated": False,
                "sections": [],
            },
            "first_message_prompt": {
                "text": "first",
                "max_chars": 8000,
                "total_chars": 5,
                "truncated": False,
                "sections": [],
            },
            "report": {
                "system_prompt": {
                    "total_chars": 6,
                    "max_chars": 40000,
                    "raw_total_chars": 6,
                    "constrained_total_chars": 6,
                    "truncated": False,
                    "truncated_by_section_limits": False,
                    "truncated_by_budget": False,
                    "sections": [],
                },
                "first_message_prompt": {
                    "total_chars": 5,
                    "max_chars": 8000,
                    "raw_total_chars": 5,
                    "constrained_total_chars": 5,
                    "truncated": False,
                    "truncated_by_section_limits": False,
                    "truncated_by_budget": False,
                    "sections": [],
                },
            },
        }

    _patch_stream_gateway(monkeypatch, [{"type": "token", "content": "Hello"}])
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.PromptContextService,
        "build_prompts",
        staticmethod(_build_prompts),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={
            "message": "Hi",
            "attachments": [
                {
                    "file_id": "00000000-0000-0000-0000-000000000001",
                    "filename": "doc.md",
                }
            ],
        },
    )
    assert response.status_code == 200
    assert "event: token" in response.text
    assert captured_flags == [True, False]


def test_stream_chat_returns_clear_oversize_message_after_attachment_fallback_fails(
    test_client, monkeypatch
):
    def _build_prompts(**_kwargs):
        raise ValueError("System prompt exceeds maximum size (50001 > 40000)")

    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
    )
    monkeypatch.setattr(
        chat_router.PromptContextService,
        "build_prompts",
        staticmethod(_build_prompts),
    )

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={
            "message": "Hi",
            "attachments": [
                {
                    "file_id": "00000000-0000-0000-0000-000000000001",
                    "filename": "doc.md",
                }
            ],
        },
    )

    assert response.status_code == 400
    payload = response.json()
    assert payload["error"]["message"] == (
        "Message context is too large. Remove some attachments or close open items and try again."
    )


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
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
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


def test_generate_title_uses_first_user_assistant_pair_by_role(
    test_client, test_db, monkeypatch
):
    user_id = "user-1"
    conversation = ConversationService.create_conversation(
        test_db, user_id, "Role Pair Title"
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {"role": "assistant", "content": "I apologize for the confusion"},
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {"role": "user", "content": "Help me plan a weekend in Lisbon"},
    )
    ConversationService.add_message(
        test_db,
        user_id,
        conversation.id,
        {"role": "assistant", "content": "Here is a two day Lisbon itinerary"},
    )

    captured: dict[str, str | None] = {
        "user_message": None,
        "assistant_message": None,
    }

    class FakeGateway:
        def __init__(self, *_args, **_kwargs):
            pass

        async def generate_title(self, **kwargs):
            captured["user_message"] = kwargs.get("user_message")
            captured["assistant_message"] = kwargs.get("assistant_message")
            return SimpleNamespace(raw_title="Lisbon Weekend Plan")

    monkeypatch.setattr(chat_router, "AIProviderGateway", FakeGateway)
    monkeypatch.setattr(
        chat_router.UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: _provider_settings()),
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
    assert captured["user_message"] == "Help me plan a weekend in Lisbon"
    assert captured["assistant_message"] == "Here is a two day Lisbon itinerary"
    assert response.json()["title"] == "Lisbon Weekend Plan"
