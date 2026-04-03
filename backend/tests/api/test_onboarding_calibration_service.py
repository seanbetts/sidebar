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
    calls: list[tuple[str, str]] = []

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None: (
                calls.append((scope, field_name))
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
    assert calls == [("assistant_soul", "purpose")]


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
        "_generate_validated_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None: {
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

    generated_fields: list[tuple[str, str]] = []

    def _generate_field(
        db,
        user_id,
        *,
        scope,
        field_name,
        answers,
        previous_name=None,
    ):
        generated_fields.append((scope, field_name))
        mapping = {
            ("assistant_soul", "success_signals"): {
                "assistant_soul": {
                    "success_signals": "Less friction and more consistent follow-through."
                }
            },
            ("assistant_soul", "operating_principles"): {
                "assistant_soul": {
                    "operating_principles": "Take initiative, reduce friction, and keep momentum visible."
                }
            },
            ("assistant_soul", "adaptation_policy"): {
                "assistant_soul": {
                    "adaptation_policy": "Adapt to durable preferences, not one-off wording."
                }
            },
        }
        return mapping[(scope, field_name)]

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update",
        staticmethod(_generate_field),
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
    assert generated_fields == [
        ("assistant_soul", "success_signals"),
        ("assistant_soul", "operating_principles"),
        ("assistant_soul", "adaptation_policy"),
    ]
    assert (
        result.assistant_soul["operating_principles"]
        == "Take initiative, reduce friction, and keep momentum visible."
    )


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
    generated_fields: list[tuple[str, str, str | None]] = []

    def _generate_field(
        db,
        user_id,
        *,
        scope,
        field_name,
        answers,
        previous_name=None,
    ):
        generated_fields.append((scope, field_name, previous_name))
        mapping = {
            ("assistant_identity", "tone"): {
                "assistant_identity": {
                    "tone": "Pragmatic, direct, and collaborative. Warm but not effusive."
                }
            },
            ("assistant_identity", "values"): {
                "assistant_identity": {
                    "values": "Clarity, pragmatism, rigor, and durable progress."
                }
            },
            ("assistant_identity", "boundaries"): {
                "assistant_identity": {
                    "boundaries": "Never invent facts, never compromise security, and preserve the user's agency."
                }
            },
            ("assistant_identity", "name"): {
                "assistant_identity": {"name": "Navigator"}
            },
        }
        return mapping[(scope, field_name)]

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update",
        staticmethod(_generate_field),
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
    assert (
        result.assistant_identity["tone"]
        == "Pragmatic, direct, and collaborative. Warm but not effusive."
    )
    assert generated_fields == [
        ("assistant_identity", "tone", None),
        ("assistant_identity", "values", None),
        ("assistant_identity", "boundaries", None),
        ("assistant_identity", "name", None),
    ]
    settings_payload = SettingsService.get_settings(test_db, user_id)
    assert settings_payload["assistant_identity"]["name"] == "Navigator"
    assert (
        settings_payload["assistant_identity"]["values"]
        == "Clarity, pragmatism, rigor, and durable progress."
    )


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
    generated_fields: list[tuple[str, str, str | None]] = []

    def _generate_field(
        db,
        user_id,
        *,
        scope,
        field_name,
        answers,
        previous_name=None,
    ):
        generated_fields.append((scope, field_name, previous_name))
        mapping = {
            ("assistant_identity", "tone"): {
                "assistant_identity": {"tone": "Direct, serious, and concise."}
            },
            ("assistant_identity", "values"): {
                "assistant_identity": {"values": "Clarity and momentum."}
            },
            ("assistant_identity", "boundaries"): {
                "assistant_identity": {"boundaries": "Do not invent facts."}
            },
            ("assistant_identity", "name"): {
                "assistant_identity": {"name": "Compass"}
            },
        }
        return mapping[(scope, field_name)]

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "_generate_validated_field_update",
        staticmethod(_generate_field),
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
    assert result.state["calibration"]["proposed_name"] == "Compass"
    assert result.assistant_identity["name"] == "Compass"
    assert generated_fields[-1] == ("assistant_identity", "name", "Navigator")


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
            lambda db, user_id, *, scope, field_name, answers, previous_name=None, repair_feedback=None: (
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
            lambda db, user_id, *, scope, field_name, answers, previous_name=None, repair_feedback=None: {
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
        "_generate_validated_field_update",
        staticmethod(
            lambda db, user_id, *, scope, field_name, answers, previous_name=None: (_ for _ in ()).throw(
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
