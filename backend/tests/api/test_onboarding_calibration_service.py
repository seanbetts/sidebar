"""Service tests for onboarding calibration state transitions."""

from __future__ import annotations

import asyncio
import json
import threading
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from api.services.ai.gateway import PromptGenerationResult
from api.services.onboarding_service import OnboardingService
from api.services.settings_service import SettingsService
from api.services.user_settings_service import UserSettingsService


def _seed_onboarding(test_db, user_id: str, *, calibration: dict | None = None) -> None:
    state = OnboardingService._resolve_state({"calibration": calibration or {}})
    UserSettingsService.upsert_settings(
        test_db,
        user_id,
        onboarding=state,
    )


def _provider_ready_state(test_db, user_id: str, *, calibration: dict | None = None) -> dict:
    state = OnboardingService._resolve_state(
        {"status": "dismissed", "calibration": calibration or {}}
    )
    UserSettingsService.upsert_settings(
        test_db,
        user_id,
        onboarding=state,
    )
    state = OnboardingService.get_onboarding_state(test_db, user_id)
    state["provider_ready"] = True
    return OnboardingService._add_derived_fields(state)


def _force_provider_ready(monkeypatch, state: dict, *, user_id: str) -> None:
    original = OnboardingService.get_onboarding_state

    monkeypatch.setattr(
        OnboardingService,
        "get_onboarding_state",
        staticmethod(
            lambda db, requested_user_id: (
                state if requested_user_id == user_id else original(db, requested_user_id)
            )
        ),
    )


def test_submit_answer_persists_answer_and_advances_prompt(test_db, monkeypatch) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-submit"
    provider_ready_state = _provider_ready_state(test_db, user_id=user_id)
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    calls: list[str] = []

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_stage_updates",
        staticmethod(
            lambda db, user_id, *, answered_prompt, answers, previous_name: (
                calls.append(answered_prompt)
                or {"assistant_soul": {"purpose": "Help the user make steady progress."}}
            )
        ),
    )

    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="primary_goal",
        answer="life_admin",
    )

    assert result.state["calibration"]["answers"]["primary_goal"] == "life_admin"
    assert result.state["calibration"]["current_prompt"] == "working_relationship"
    assert result.assistant_identity is None
    assert result.assistant_soul["purpose"] == "Help the user make steady progress."
    assert calls == ["primary_goal"]


def test_submit_answer_allows_revisiting_primary_goal_and_clears_downstream_answers(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-revisit-primary"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "in_progress",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "keep_me_on_track",
                "tone_preferences": "warm,serious,concise,casual,supportive",
            },
            "proposed_name": "Navigator",
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_stage_updates",
        staticmethod(
            lambda db, user_id, *, answered_prompt, answers, previous_name: {
                "assistant_soul": {"purpose": "Help the user make steady progress."}
            }
        ),
    )

    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="primary_goal",
        answer="personal_productivity,notes_and_ideas",
    )

    assert (
        result.state["calibration"]["answers"]["primary_goal"]
        == "personal_productivity,notes_and_ideas"
    )
    assert result.state["calibration"]["answers"]["working_relationship"] is None
    assert result.state["calibration"]["answers"]["tone_preferences"] is None
    assert result.state["calibration"]["proposed_name"] is None
    assert result.state["calibration"]["status"] == "in_progress"
    assert result.state["calibration"]["current_prompt"] == "working_relationship"


def test_submit_answer_allows_revisiting_working_relationship_and_clears_tone(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-revisit-relationship"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "keep_me_on_track",
                "tone_preferences": "warm,serious,concise,casual,supportive",
            },
            "proposed_name": "Navigator",
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)

    generated_stages: list[str] = []

    def _generate_stage(
        db,
        user_id,
        *,
        answered_prompt,
        answers,
        previous_name,
    ):
        generated_stages.append(answered_prompt)
        return {
            "assistant_soul": {
                "success_signals": "Less friction and more consistent follow-through.",
                "operating_principles": "Take initiative, reduce friction, and keep momentum visible.",
                "adaptation_policy": "Adapt to durable preferences, not one-off wording.",
            }
        }

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_stage_updates",
        staticmethod(_generate_stage),
    )

    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="working_relationship",
        answer="take_initiative_with_me",
    )

    assert result.state["calibration"]["answers"]["primary_goal"] == "life_admin"
    assert (
        result.state["calibration"]["answers"]["working_relationship"]
        == "take_initiative_with_me"
    )
    assert result.state["calibration"]["answers"]["tone_preferences"] is None
    assert result.state["calibration"]["proposed_name"] is None
    assert result.state["calibration"]["status"] == "in_progress"
    assert result.state["calibration"]["current_prompt"] == "tone_preferences"
    assert generated_stages == ["working_relationship"]
    assert (
        result.assistant_soul["operating_principles"]
        == "Take initiative, reduce friction, and keep momentum visible."
    )


def test_generate_stage_updates_parallelizes_independent_working_relationship_fields(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-stage-parallel"
    active_calls = 0
    max_active_calls = 0
    lock = threading.Lock()

    monkeypatch.setattr(
        UserSettingsService,
        "get_settings",
        staticmethod(
            lambda db, requested_user_id: SimpleNamespace(
                assistant_identity={},
                assistant_soul={},
            )
        ),
    )
    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_render_field_prompt",
        staticmethod(
            lambda *,
            scope,
            field_name,
            answers,
            current_identity,
            current_soul,
            previous_name,
            repair_feedback: f"{scope}.{field_name}"
        ),
    )

    async def fake_generate_text(
        self,
        *,
        prompt,
        settings_record,
        system_prompt=None,
        preferred_provider=None,
        provider_key_lookup=None,
        max_output_tokens=800,
        temperature=0.3,
    ) -> PromptGenerationResult:
        nonlocal active_calls, max_active_calls
        with lock:
            active_calls += 1
            max_active_calls = max(max_active_calls, active_calls)
        await asyncio.sleep(0.05)
        with lock:
            active_calls -= 1
        scope, field_name = prompt.split(".", 1)
        return PromptGenerationResult(
            raw_text=json.dumps({scope: {field_name: f"{field_name} prose"}}),
            provider="openai",
        )

    monkeypatch.setattr(
        "api.services.ai.gateway.AIProviderGateway.generate_text",
        fake_generate_text,
    )

    updates = OnboardingCalibrationService._generate_stage_updates(
        test_db,
        user_id,
        answered_prompt="working_relationship",
        answers={
            "primary_goal": "life_admin",
            "working_relationship": "collaborative",
            "tone_preferences": None,
        },
        previous_name=None,
    )

    assert max_active_calls >= 2
    assert updates == {
        "assistant_soul": {
            "success_signals": "success_signals prose",
            "operating_principles": "operating_principles prose",
            "adaptation_policy": "adaptation_policy prose",
        }
    }


def test_submit_answer_requires_provider_ready(test_db, monkeypatch) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-provider-gate"
    _seed_onboarding(test_db, user_id=user_id)

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService.submit_answer(
            test_db,
            user_id,
            prompt="primary_goal",
            answer="life_admin",
        )

    assert "provider" in str(exc_info.value).lower()
    state = OnboardingService.get_onboarding_state(test_db, user_id)
    assert state["calibration"]["answers"]["primary_goal"] is None
    settings_payload = SettingsService.get_settings(test_db, user_id)
    assert settings_payload["assistant_identity"]["name"] == "sideBar"
    assert settings_payload["assistant_soul"]["purpose"] is None


def test_submit_answer_generates_assistant_configuration_after_tone(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-generate"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "in_progress",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
            },
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    generated_stages: list[tuple[str, str | None]] = []

    def _generate_stage(
        db,
        user_id,
        *,
        answered_prompt,
        answers,
        previous_name,
    ):
        generated_stages.append((answered_prompt, previous_name))
        return {
            "assistant_identity": {
                "tone": "Pragmatic, direct, and collaborative. Warm but not effusive.",
                "values": "Clarity, pragmatism, rigor, and durable progress.",
                "boundaries": "Never invent facts, never compromise security, and preserve the user's agency.",
            }
        }

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_stage_updates",
        staticmethod(_generate_stage),
    )
    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="tone_preferences",
        answer="direct_but_kind",
    )

    assert result.state["calibration"]["status"] == "awaiting_name_acceptance"
    assert result.state["calibration"]["proposed_name"] is None
    assert result.assistant_identity["name"] == "sideBar"
    assert (
        result.assistant_identity["tone"]
        == "Pragmatic, direct, and collaborative. Warm but not effusive."
    )
    assert generated_stages == [("tone_preferences", None)]
    settings_payload = SettingsService.get_settings(test_db, user_id)
    assert settings_payload["assistant_identity"]["name"] == "sideBar"
    assert (
        settings_payload["assistant_identity"]["values"]
        == "Clarity, pragmatism, rigor, and durable progress."
    )
    persisted_state = OnboardingService._resolve_state(
        UserSettingsService.get_settings(test_db, user_id).onboarding
    )
    assert persisted_state["calibration"]["status"] == "awaiting_name_acceptance"
    assert persisted_state["calibration"]["current_prompt"] == "tone_preferences"
    assert persisted_state["calibration"]["proposed_name"] is None


def test_submit_answer_allows_revisiting_tone_while_awaiting_name_acceptance(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-revisit-tone"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "take_initiative_with_me",
                "tone_preferences": "warm,serious,concise,casual,supportive",
            },
            "proposed_name": "Navigator",
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    generated_stages: list[tuple[str, str | None]] = []

    def _generate_stage(
        db,
        user_id,
        *,
        answered_prompt,
        answers,
        previous_name,
    ):
        generated_stages.append((answered_prompt, previous_name))
        return {
            "assistant_identity": {
                "tone": "Direct, serious, and concise.",
                "values": "Clarity and momentum.",
                "boundaries": "Do not invent facts.",
            }
        }

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_stage_updates",
        staticmethod(_generate_stage),
    )
    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="tone_preferences",
        answer="direct,serious,concise,casual,challenging",
    )

    assert result.state["calibration"]["status"] == "awaiting_name_acceptance"
    assert (
        result.state["calibration"]["answers"]["tone_preferences"]
        == "direct,serious,concise,casual,challenging"
    )
    assert result.state["calibration"]["proposed_name"] is None
    assert result.assistant_identity["name"] == "sideBar"
    assert generated_stages == [("tone_preferences", "Navigator")]


def test_regenerate_name_can_generate_initial_name_when_missing(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-regenerate-initial"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "direct_but_kind",
            },
            "proposed_name": None,
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    SettingsService.update_agent_settings(
        test_db,
        user_id,
        {
            "assistant_identity": {
                "tone": "Direct and warm.",
            },
            "assistant_soul": {
                "purpose": "Help with steady life admin.",
            },
        },
        reason="Seed calibration state",
    )

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None: {
                "assistant_identity": {"name": "Navigator"}
            }
        ),
    )

    result = OnboardingCalibrationService.regenerate_name(test_db, user_id)

    assert result.state["calibration"]["proposed_name"] == "Navigator"
    assert result.assistant_identity["name"] == "Navigator"


def test_submit_answer_then_regenerate_name_succeeds_with_persisted_state(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-tone-then-name"
    _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "in_progress",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
            },
        },
    )
    original_get_onboarding_state = OnboardingService.get_onboarding_state

    monkeypatch.setattr(
        OnboardingService,
        "get_onboarding_state",
        staticmethod(
            lambda db, requested_user_id: (
                {
                    **original_get_onboarding_state(db, requested_user_id),
                    "provider_ready": True,
                }
                if requested_user_id == user_id
                else original_get_onboarding_state(db, requested_user_id)
            )
        ),
    )

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_stage_updates",
        staticmethod(
            lambda db, user_id, *, answered_prompt, answers, previous_name: {
                "assistant_identity": {
                    "tone": "Pragmatic, direct, and collaborative.",
                    "values": "Clarity, rigor, and durable progress.",
                    "boundaries": "Never invent facts or compromise security.",
                }
            }
        ),
    )

    OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="tone_preferences",
        answer="direct_but_kind",
    )

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None: {
                "assistant_identity": {"name": "Navigator"}
            }
        ),
    )

    result = OnboardingCalibrationService.regenerate_name(test_db, user_id)

    assert result.state["calibration"]["status"] == "awaiting_name_acceptance"
    assert result.state["calibration"]["proposed_name"] == "Navigator"
    assert result.assistant_identity["name"] == "Navigator"


def test_regenerate_name_only_updates_proposed_name(test_db, monkeypatch) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-regenerate"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "direct_but_kind",
            },
            "proposed_name": "Navigator",
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    SettingsService.update_agent_settings(
        test_db,
        user_id,
        {
            "assistant_identity": {
                "name": "Navigator",
                "tone": "Direct and warm.",
            },
            "assistant_soul": {
                "purpose": "Help with steady life admin.",
            },
        },
        reason="Seed calibration state",
    )

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None: {
                "assistant_identity": {"name": "Compass"}
            }
        ),
    )

    result = OnboardingCalibrationService.regenerate_name(test_db, user_id)

    assert result.state["calibration"]["proposed_name"] == "Compass"
    assert result.state["status"] == "dismissed"
    assert result.assistant_identity["name"] == "Compass"
    assert result.assistant_soul is None
    settings_payload = SettingsService.get_settings(test_db, user_id)
    assert settings_payload["assistant_identity"]["name"] == "Compass"
    assert settings_payload["assistant_soul"]["purpose"] == "Help with steady life admin."


def test_regenerate_name_requires_provider_ready(test_db) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-regenerate-provider-gate"
    _seed_onboarding(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "direct_but_kind",
            },
            "proposed_name": "Navigator",
        },
    )

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService.regenerate_name(test_db, user_id)

    assert "provider" in str(exc_info.value).lower()


def test_accept_name_marks_calibration_completed(test_db, monkeypatch) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-accept"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "direct_but_kind",
            },
            "proposed_name": "Navigator",
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)

    result = OnboardingCalibrationService.accept_name(test_db, user_id)

    assert result.state["calibration"]["status"] == "completed"
    assert result.state["calibration"]["completed_at"] is not None
    assert result.state["calibration"]["proposed_name"] == "Navigator"


def test_accept_name_requires_provider_ready(test_db) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-accept-provider-gate"
    _seed_onboarding(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "direct_but_kind",
            },
            "proposed_name": "Navigator",
        },
    )

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService.accept_name(test_db, user_id)

    assert "provider" in str(exc_info.value).lower()


def test_accept_name_requires_proposed_name(test_db, monkeypatch) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-accept-no-name"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "direct_but_kind",
            },
            "proposed_name": None,
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService.accept_name(test_db, user_id)

    assert "proposed" in str(exc_info.value).lower()


def test_submit_answer_retries_generation_after_validation_failure(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-retry"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "in_progress",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
            },
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)

    calls: list[str | None] = []

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_model_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None, repair_feedback=None, generation_context=None, current_identity=None, current_soul=None: (
                calls.append(repair_feedback)
                or (
                    {"assistant_identity": {"name": "x" * 121}}
                    if repair_feedback is None
                    else {"assistant_identity": {"name": "Navigator"}}
                )
            )
        ),
    )

    result = OnboardingCalibrationService._generate_validated_field_update(
        test_db,
        user_id,
        scope="assistant_identity",
        field_name="name",
        answers={"primary_goal": "life_admin"},
        previous_name=None,
    )

    assert result == {"assistant_identity": {"name": "Navigator"}}
    assert calls == [
        None,
        "assistant_identity.name exceeds max length (120 characters)",
    ]


def test_submit_answer_surfaces_retryable_error_after_second_validation_failure(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-retry-fail"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "in_progress",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
            },
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_model_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None, repair_feedback=None, generation_context=None, current_identity=None, current_soul=None: {
                "assistant_identity": {"name": "x" * 121},
            }
        ),
    )

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService._generate_validated_field_update(
            test_db,
            user_id,
            scope="assistant_identity",
            field_name="name",
            answers={"primary_goal": "life_admin"},
            previous_name=None,
        )

    assert "choose a name" in str(exc_info.value.detail).lower()


def test_submit_answer_persists_tone_answer_when_generation_fails(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-tone-persists"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "in_progress",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
            },
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_stage_updates",
        staticmethod(
            lambda db, user_id, *, answered_prompt, answers, previous_name: (_ for _ in ()).throw(
                HTTPException(status_code=503, detail="Calibration generation failed")
            )
        ),
    )

    with pytest.raises(HTTPException):
        OnboardingCalibrationService.submit_answer(
            test_db,
            user_id,
            prompt="tone_preferences",
            answer="direct_but_kind",
        )

    settings_record = UserSettingsService.get_settings(test_db, user_id)
    persisted_state = OnboardingService._resolve_state(settings_record.onboarding)
    assert (
        persisted_state["calibration"]["answers"]["tone_preferences"]
        == "direct_but_kind"
    )
    assert persisted_state["calibration"]["status"] == "in_progress"
    assert persisted_state["calibration"]["current_prompt"] == "tone_preferences"
    settings_payload = SettingsService.get_settings(test_db, user_id)
    assert settings_payload["assistant_identity"]["name"] == "sideBar"
    assert settings_payload["assistant_soul"]["purpose"] is None


def test_regenerate_name_failure_preserves_existing_identity_fields(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import (
        GenerationContext,
        OnboardingCalibrationService,
    )

    user_id = "calibration-name-failure-persists-identity"
    provider_ready_state = _provider_ready_state(
        test_db,
        user_id=user_id,
        calibration={
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "warm,serious,concise,casual,supportive",
            },
            "proposed_name": None,
        },
    )
    _force_provider_ready(monkeypatch, provider_ready_state, user_id=user_id)
    SettingsService.update_agent_settings(
        test_db,
        user_id,
        {
            "assistant_identity": {
                "tone": "Pragmatic, direct, and collaborative.",
                "values": "Clarity, rigor, and honesty.",
                "boundaries": "Never mislead or manipulate.",
            }
        },
        reason="Seed calibration identity",
    )
    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_build_generation_context",
        staticmethod(
            lambda db, requested_user_id: GenerationContext(
                settings_snapshot=SimpleNamespace(ai_primary_provider="anthropic"),
                current_identity={
                    "tone": "Pragmatic, direct, and collaborative.",
                    "values": "Clarity, rigor, and honesty.",
                    "boundaries": "Never mislead or manipulate.",
                },
                current_soul={},
                provider_keys={"anthropic": "test-key", "openai": None, "google": None},
            )
        ),
    )
    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update_for_context",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name, generation_context, current_identity, current_soul: (_ for _ in ()).throw(
                HTTPException(
                    status_code=503,
                    detail=(
                        "I couldn't choose a name just yet. "
                        "Your setup is saved, please try again."
                    ),
                )
            )
        ),
    )

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService.regenerate_name(test_db, user_id)

    assert exc_info.value.status_code == 503
    assert "choose a name" in str(exc_info.value.detail).lower()

    settings_payload = SettingsService.get_settings(test_db, user_id)
    assert (
        settings_payload["assistant_identity"]["tone"]
        == "Pragmatic, direct, and collaborative."
    )
    assert (
        settings_payload["assistant_identity"]["values"]
        == "Clarity, rigor, and honesty."
    )
    assert (
        settings_payload["assistant_identity"]["boundaries"]
        == "Never mislead or manipulate."
    )
    persisted_state = OnboardingService._resolve_state(
        UserSettingsService.get_settings(test_db, user_id).onboarding
    )
    assert persisted_state["calibration"]["status"] == "awaiting_name_acceptance"
    assert persisted_state["calibration"]["current_prompt"] == "tone_preferences"
    assert persisted_state["calibration"]["proposed_name"] is None


def test_generate_validated_field_update_maps_name_provider_failure_to_retryable_message(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import (
        GenerationContext,
        OnboardingCalibrationService,
    )

    user_id = "calibration-name-provider-failure"

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_build_generation_context",
        staticmethod(
            lambda db, requested_user_id: GenerationContext(
                settings_snapshot=SimpleNamespace(ai_primary_provider="anthropic"),
                current_identity={},
                current_soul={},
                provider_keys={"anthropic": "test-key", "openai": None, "google": None},
            )
        ),
    )

    async def fake_generate_text(
        self,
        *,
        prompt,
        settings_record,
        system_prompt=None,
        preferred_provider=None,
        provider_key_lookup=None,
        max_output_tokens=800,
        temperature=0.3,
    ) -> PromptGenerationResult:
        del (
            self,
            prompt,
            settings_record,
            system_prompt,
            preferred_provider,
            provider_key_lookup,
            max_output_tokens,
            temperature,
        )
        raise RuntimeError("provider internal error")

    monkeypatch.setattr(
        "api.services.ai.gateway.AIProviderGateway.generate_text",
        fake_generate_text,
    )

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService._generate_validated_field_update(
            test_db,
            user_id,
            scope="assistant_identity",
            field_name="name",
            answers={
                "primary_goal": "life_admin",
                "working_relationship": "collaborative",
                "tone_preferences": "warm,serious,concise,casual,supportive",
            },
            previous_name=None,
        )

    assert exc_info.value.status_code == 503
    assert "choose a name" in str(exc_info.value.detail).lower()


def test_build_generation_context_only_loads_primary_provider_key(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-primary-provider-only"
    requested_providers: list[str] = []

    monkeypatch.setattr(
        UserSettingsService,
        "get_settings",
        staticmethod(
            lambda db, requested_user_id: SimpleNamespace(
                ai_primary_provider="openai",
                assistant_identity={},
                assistant_soul={},
            )
        ),
    )
    monkeypatch.setattr(
        "api.services.onboarding_calibration_service.UserAIProviderKeyService.get_active_key",
        staticmethod(
            lambda db, requested_user_id, provider: (
                requested_providers.append(provider) or f"{provider}-key"
            )
        ),
    )

    context = OnboardingCalibrationService._build_generation_context(test_db, user_id)

    assert requested_providers == ["openai"]
    assert context.provider_keys == {"openai": "openai-key"}


def test_render_field_prompt_uses_compact_json_snapshots() -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    prompt = OnboardingCalibrationService._render_field_prompt(
        scope="assistant_soul",
        field_name="purpose",
        answers={
            "primary_goal": "notes_and_ideas",
            "working_relationship": "collaborative",
            "tone_preferences": "direct_but_kind",
        },
        current_identity={
            "tone": "Direct and warm.",
            "values": "Clarity and rigor.",
        },
        current_soul={
            "purpose": "Help the user make progress.",
        },
        previous_name=None,
        repair_feedback=None,
    )

    assert '{"purpose":"Help the user make progress."}' in prompt
    assert (
        '{"tone":"Direct and warm.","values":"Clarity and rigor."}' in prompt
    )
    assert '\n    "purpose"' not in prompt


def test_render_field_prompt_includes_exact_json_shape_in_retry_guidance() -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    prompt = OnboardingCalibrationService._render_field_prompt(
        scope="assistant_identity",
        field_name="boundaries",
        answers={
            "primary_goal": "notes_and_ideas",
            "working_relationship": "collaborative",
            "tone_preferences": "direct_but_kind",
        },
        current_identity={
            "tone": "Direct and warm.",
        },
        current_soul={
            "purpose": "Help the user make progress.",
        },
        previous_name=None,
        repair_feedback="Generated invalid JSON for assistant_identity.boundaries",
    )

    assert "Retry guidance:" in prompt
    assert (
        '{"assistant_identity":{"boundaries":"<write the field value here>"}}'
        in prompt
    )
    assert "No markdown, no explanation, and no extra keys." in prompt


def test_generate_model_field_update_uses_calibration_token_budgets(
    test_db,
    monkeypatch,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    user_id = "calibration-token-budgets"
    budgets: list[tuple[str, int]] = []

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_build_generation_context",
        staticmethod(
            lambda db, requested_user_id: SimpleNamespace(
                settings_snapshot=SimpleNamespace(ai_primary_provider="openai"),
                current_identity={},
                current_soul={},
                provider_keys={"openai": "test-key"},
            )
        ),
    )
    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_render_field_prompt",
        staticmethod(
            lambda *,
            scope,
            field_name,
            answers,
            current_identity,
            current_soul,
            previous_name,
            repair_feedback: f"{scope}.{field_name}"
        ),
    )

    async def fake_generate_text(
        self,
        *,
        prompt,
        settings_record,
        system_prompt=None,
        preferred_provider=None,
        provider_key_lookup=None,
        max_output_tokens=800,
        temperature=0.3,
    ) -> PromptGenerationResult:
        budgets.append((prompt, max_output_tokens))
        scope, field_name = prompt.split(".", 1)
        return PromptGenerationResult(
            raw_text=json.dumps({scope: {field_name: "generated"}}),
            provider="openai",
        )

    monkeypatch.setattr(
        "api.services.ai.gateway.AIProviderGateway.generate_text",
        fake_generate_text,
    )

    OnboardingCalibrationService._generate_model_field_update(
        test_db,
        user_id,
        scope="assistant_identity",
        field_name="name",
        answers={"primary_goal": "life_admin"},
        previous_name=None,
        repair_feedback=None,
    )
    OnboardingCalibrationService._generate_model_field_update(
        test_db,
        user_id,
        scope="assistant_identity",
        field_name="tone",
        answers={"primary_goal": "life_admin"},
        previous_name=None,
        repair_feedback=None,
    )
    OnboardingCalibrationService._generate_model_field_update(
        test_db,
        user_id,
        scope="assistant_soul",
        field_name="operating_principles",
        answers={"primary_goal": "life_admin"},
        previous_name=None,
        repair_feedback=None,
    )

    assert budgets == [
        ("assistant_identity.name", 48),
        ("assistant_identity.tone", 220),
        ("assistant_soul.operating_principles", 320),
    ]


def test_parse_generated_json_object_wraps_plain_text_response() -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    parsed = OnboardingCalibrationService._parse_generated_json_object(
        "Never fabricate facts or credentials.",
        scope="assistant_identity",
        field_name="boundaries",
    )

    assert parsed == {
        "assistant_identity": {
            "boundaries": "Never fabricate facts or credentials."
        }
    }


def test_parse_generated_json_object_wraps_top_level_field_payload() -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    parsed = OnboardingCalibrationService._parse_generated_json_object(
        json.dumps({"boundaries": "Never fabricate facts or credentials."}),
        scope="assistant_identity",
        field_name="boundaries",
    )

    assert parsed == {
        "assistant_identity": {
            "boundaries": "Never fabricate facts or credentials."
        }
    }


def test_parse_generated_json_object_wraps_scope_string_payload() -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    parsed = OnboardingCalibrationService._parse_generated_json_object(
        json.dumps({"assistant_identity": "Never fabricate facts or credentials."}),
        scope="assistant_identity",
        field_name="boundaries",
    )

    assert parsed == {
        "assistant_identity": {
            "boundaries": "Never fabricate facts or credentials."
        }
    }


def test_parse_generated_json_object_extracts_requested_field_from_extra_keys() -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    parsed = OnboardingCalibrationService._parse_generated_json_object(
        json.dumps(
            {
                "assistant_identity": {
                    "boundaries": "Never fabricate facts or credentials.",
                    "_meta": {"reason": "extra"},
                },
                "note": "extra top-level commentary",
            }
        ),
        scope="assistant_identity",
        field_name="boundaries",
    )

    assert parsed == {
        "assistant_identity": {
            "boundaries": "Never fabricate facts or credentials."
        }
    }
