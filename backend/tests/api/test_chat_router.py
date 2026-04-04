import json
import logging
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest

from api.config import settings
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
from api.services.conversation_service import ConversationService


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


def test_stream_chat_forwards_memory_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [{"type": "memory_created", "data": {"id": "memory-1"}}],
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
    assert "event: memory_created" in body
    assert 'data: {"id": "memory-1"}' in body
    assert "event: complete" in body


def test_stream_chat_forwards_assistant_identity_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "assistant_identity_updated",
                "data": {
                    "assistant_identity": {"name": "Navigator"},
                    "assistant_identity_meta": {
                        "updated_at": "2026-02-18T00:00:00Z",
                        "version": 2,
                    },
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
    assert "event: assistant_identity_updated" in body
    assert '"assistant_identity": {"name": "Navigator"}' in body
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


def test_stream_chat_forwards_other_preferences_events(test_client, monkeypatch):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "other_preferences_updated",
                "data": {
                    "weather_unit": "fahrenheit",
                    "biometric_unlock_enabled": True,
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
    assert "event: other_preferences_updated" in body
    assert '"weather_unit": "fahrenheit"' in body
    assert '"biometric_unlock_enabled": true' in body
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


def test_stream_chat_forwards_conversation_title_updated_events(
    test_client, monkeypatch
):
    _patch_stream_gateway(
        monkeypatch,
        [
            {
                "type": "conversation_title_updated",
                "data": {
                    "id": "conv-1",
                    "title": "Renamed",
                    "titleGenerated": False,
                    "updatedAt": "2026-03-28T12:00:00Z",
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
    assert "event: conversation_title_updated" in body
    assert '"title": "Renamed"' in body
    assert '"titleGenerated": false' in body
    assert '"updatedAt": "2026-03-28T12:00:00Z"' in body
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


def test_stream_chat_injects_bootstrap_history_on_first_turn(
    test_client, monkeypatch
):
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
            json={"message": "Current question", "conversation_id": str(conversation.id)},
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
                {"file_id": "00000000-0000-0000-0000-000000000001", "filename": "doc.md"}
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
                {"file_id": "00000000-0000-0000-0000-000000000001", "filename": "doc.md"}
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
