"""Service tests for onboarding calibration state transitions."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

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

    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="primary_goal",
        answer="life_admin",
    )

    assert result.state["calibration"]["answers"]["primary_goal"] == "life_admin"
    assert result.state["calibration"]["current_prompt"] == "working_relationship"
    assert result.assistant_identity is None
    assert result.assistant_soul is None


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

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_calibration_payload",
        staticmethod(
            lambda *, answers, previous_name=None, repair_mode=False, validation_error=None: {
                "assistant_identity": {
                    "name": "Navigator",
                    "tone": "Direct and warm.",
                    "values": "Clarity and momentum.",
                    "boundaries": "Do not invent facts.",
                },
                "assistant_soul": {
                    "purpose": "Help with steady life admin.",
                    "operating_principles": "Be practical and calm.",
                    "adaptation_policy": "Adapt to durable preferences.",
                    "success_signals": "Less friction and more follow-through.",
                },
                "confirmation_text": "Navigator is ready for review.",
            }
        ),
    )

    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="tone_preferences",
        answer="direct_but_kind",
    )

    assert result.state["calibration"]["status"] == "awaiting_name_acceptance"
    assert result.state["calibration"]["proposed_name"] == "Navigator"
    assert result.assistant_identity["name"] == "Navigator"
    assert result.assistant_soul["purpose"] == "Help with steady life admin."
    settings_payload = SettingsService.get_settings(test_db, user_id)
    assert settings_payload["assistant_identity"]["name"] == "Navigator"
    assert settings_payload["assistant_soul"]["purpose"] == "Help with steady life admin."


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
        "_generate_name_candidate",
        staticmethod(lambda *, answers, previous_name=None: "Compass"),
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

    calls: list[tuple[bool, str | None]] = []

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_calibration_payload",
        staticmethod(
            lambda *, answers, previous_name=None, repair_mode=False, validation_error=None: (
                calls.append(
                    (
                        repair_mode,
                        str(validation_error.detail) if validation_error else None,
                    )
                )
                or (
                    {
                        "assistant_identity": {"name": "x" * 121},
                        "assistant_soul": {"purpose": "Help clearly."},
                        "confirmation_text": "try one",
                    }
                    if not repair_mode
                    else {
                        "assistant_identity": {"name": "Navigator"},
                        "assistant_soul": {"purpose": "Help clearly."},
                        "confirmation_text": "try two",
                    }
                )
            )
        ),
    )

    result = OnboardingCalibrationService.submit_answer(
        test_db,
        user_id,
        prompt="tone_preferences",
        answer="direct_but_kind",
    )

    assert result.assistant_identity["name"] == "Navigator"
    assert result.state["calibration"]["status"] == "awaiting_name_acceptance"
    assert calls == [
        (False, None),
        (True, "assistant_identity.name exceeds max length (120 characters)"),
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
        "_generate_calibration_payload",
        staticmethod(
            lambda *, answers, previous_name=None, repair_mode=False, validation_error=None: {
                "assistant_identity": {"name": "x" * 121},
                "assistant_soul": {"purpose": "Help clearly."},
                "confirmation_text": "still invalid",
            }
        ),
    )

    with pytest.raises(HTTPException) as exc_info:
        OnboardingCalibrationService.submit_answer(
            test_db,
            user_id,
            prompt="tone_preferences",
            answer="direct_but_kind",
        )

    assert "retry" in str(exc_info.value).lower()


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
        "_generate_calibration_payload",
        staticmethod(
            lambda *, answers, previous_name=None, repair_mode=False, validation_error=None: {
                "assistant_identity": {"name": "x" * 121},
                "assistant_soul": {"purpose": "Help clearly."},
                "confirmation_text": "invalid",
            }
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
