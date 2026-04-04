"""Unit tests for OnboardingService."""

import pytest
from fastapi import HTTPException

from api.services.onboarding_service import OnboardingService


# ---------------------------------------------------------------------------
# _resolve_state
# ---------------------------------------------------------------------------

def test_resolve_state_returns_defaults_for_none() -> None:
    state = OnboardingService._resolve_state(None)
    assert state["status"] == "not_started"
    assert state["intent"] is None
    assert state["calibration"]["status"] == "not_started"
    assert state["calibration"]["current_prompt"] == "primary_goal"
    assert state["calibration"]["answers"]["primary_goal"] is None
    assert state["calibration"]["answers"]["working_relationship"] is None
    assert state["calibration"]["answers"]["tone_preferences"] is None
    assert state["calibration"]["proposed_name"] is None
    assert state["calibration"]["completed_at"] is None
    assert state["milestones"]["provider_connected"] is None
    assert state["milestones"]["first_outcome_completed"] is None
    assert state["permissions"]["location"] == "not_asked"
    assert state["permissions"]["notifications"] == "not_asked"
    assert state["last_prompted_at"] is None


def test_resolve_state_preserves_valid_values() -> None:
    raw = {
        "status": "in_progress",
        "intent": "notes",
        "calibration": {
            "status": "in_progress",
            "current_prompt": "working_relationship",
            "answers": {
                "primary_goal": "life_admin",
                "working_relationship": None,
                "tone_preferences": "direct",
            },
            "proposed_name": "Navigator",
            "completed_at": None,
        },
        "milestones": {"provider_connected": "2026-03-13T10:00:00Z"},
        "permissions": {"location": "granted", "notifications": "denied"},
        "last_prompted_at": "2026-03-13T09:00:00Z",
    }
    state = OnboardingService._resolve_state(raw)
    assert state["status"] == "in_progress"
    assert state["intent"] == "notes"
    assert state["calibration"]["status"] == "in_progress"
    assert state["calibration"]["current_prompt"] == "working_relationship"
    assert state["calibration"]["answers"]["primary_goal"] == "life_admin"
    assert state["calibration"]["answers"]["tone_preferences"] == "direct"
    assert state["calibration"]["proposed_name"] == "Navigator"
    assert state["milestones"]["provider_connected"] == "2026-03-13T10:00:00Z"
    assert state["milestones"]["first_outcome_completed"] is None
    assert state["permissions"]["location"] == "granted"
    assert state["permissions"]["notifications"] == "denied"
    assert state["last_prompted_at"] == "2026-03-13T09:00:00Z"


def test_resolve_state_resets_invalid_status() -> None:
    state = OnboardingService._resolve_state({"status": "bogus"})
    assert state["status"] == "not_started"


def test_resolve_state_resets_invalid_intent() -> None:
    state = OnboardingService._resolve_state({"intent": "bogus"})
    assert state["intent"] is None


def test_resolve_state_resets_invalid_permission_state() -> None:
    raw = {"permissions": {"location": "maybe", "notifications": "granted"}}
    state = OnboardingService._resolve_state(raw)
    assert state["permissions"]["location"] == "not_asked"
    assert state["permissions"]["notifications"] == "granted"


def test_resolve_state_ignores_extra_milestone_keys() -> None:
    raw = {"milestones": {"provider_connected": "ts", "unknown_key": "ts"}}
    state = OnboardingService._resolve_state(raw)
    assert "unknown_key" not in state["milestones"]
    assert state["milestones"]["provider_connected"] == "ts"


# ---------------------------------------------------------------------------
# _validate_updates
# ---------------------------------------------------------------------------

def test_validate_updates_rejects_unknown_fields() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates({"foo": "bar"})
    assert exc.value.status_code == 400
    assert "foo" in exc.value.detail


def test_validate_updates_rejects_invalid_status() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates({"status": "bogus"})
    assert exc.value.status_code == 400


def test_validate_updates_rejects_invalid_intent() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates({"intent": "bogus"})
    assert exc.value.status_code == 400


def test_validate_updates_rejects_invalid_milestone_key() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates({"milestones": {"bad_key": "ts"}})
    assert exc.value.status_code == 400


def test_validate_updates_rejects_invalid_milestone_value() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates(
            {"milestones": {"provider_connected": 12345}}
        )
    assert exc.value.status_code == 400


def test_validate_updates_rejects_invalid_permission_key() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates({"permissions": {"camera": "granted"}})
    assert exc.value.status_code == 400


def test_validate_updates_rejects_invalid_permission_value() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates({"permissions": {"location": "maybe"}})
    assert exc.value.status_code == 400


def test_validate_updates_accepts_valid_payload() -> None:
    # Must not raise
    OnboardingService._validate_updates(
        {
            "status": "in_progress",
            "intent": "tasks",
            "calibration": {
                "status": "in_progress",
                "current_prompt": "tone_preferences",
                "answers": {"primary_goal": "life_admin"},
            },
            "milestones": {"provider_connected": "2026-03-13T10:00:00Z"},
            "permissions": {"location": "granted"},
        }
    )


def test_validate_updates_accepts_null_intent() -> None:
    OnboardingService._validate_updates({"intent": None})


def test_validate_updates_accepts_null_milestone() -> None:
    OnboardingService._validate_updates({"milestones": {"provider_connected": None}})


def test_validate_updates_rejects_invalid_last_prompted_at() -> None:
    with pytest.raises(HTTPException) as exc:
        OnboardingService._validate_updates({"last_prompted_at": 12345})
    assert exc.value.status_code == 400


def test_validate_updates_accepts_null_last_prompted_at() -> None:
    OnboardingService._validate_updates({"last_prompted_at": None})


def test_validate_updates_accepts_calibration_payload() -> None:
    OnboardingService._validate_updates(
        {
            "calibration": {
                "status": "in_progress",
                "current_prompt": "primary_goal",
                "answers": {
                    "primary_goal": "life_admin",
                    "working_relationship": None,
                },
                "proposed_name": "Navigator",
                "completed_at": None,
            }
        }
    )


# ---------------------------------------------------------------------------
# derived onboarding helpers
# ---------------------------------------------------------------------------


def test_is_onboarding_complete_false_for_default_state() -> None:
    state = OnboardingService._resolve_state(None)

    assert OnboardingService.is_onboarding_complete(state) is False


def test_is_onboarding_complete_false_for_completed_status_without_completion_milestones() -> None:
    state = OnboardingService._resolve_state({"status": "completed"})
    state["provider_ready"] = True

    assert OnboardingService.is_onboarding_complete(state) is False


def test_is_onboarding_complete_false_when_calibration_is_incomplete() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "completed",
            "milestones": {"secondary_tour_seen": "2026-03-31T11:00:00Z"},
            "calibration": {"status": "in_progress"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.is_onboarding_complete(state) is False


def test_current_onboarding_step_defaults_to_phase1_wizard() -> None:
    state = OnboardingService._resolve_state(None)

    assert OnboardingService.current_onboarding_step(state) == "phase1_wizard"


def test_current_onboarding_step_uses_provider_recovery_when_dismissed_without_key() -> None:
    state = OnboardingService._resolve_state({"status": "dismissed"})
    state["provider_ready"] = False

    assert OnboardingService.current_onboarding_step(state) == "provider_recovery"


def test_current_onboarding_step_uses_soul_calibration_when_provider_ready_and_status_is_not_started() -> None:
    state = OnboardingService._resolve_state({"status": "not_started"})
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "soul_calibration"


def test_current_onboarding_step_uses_soul_calibration_when_provider_ready_and_calibration_is_not_completed() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "dismissed",
            "calibration": {"status": "in_progress"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "soul_calibration"


def test_current_onboarding_step_uses_feature_discovery_when_provider_ready_even_if_permissions_are_missing() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "dismissed",
            "milestones": {"provider_connected": "2026-03-31T10:00:00Z"},
            "calibration": {"status": "completed"},
            "permissions": {"location": "denied", "notifications": "granted"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "feature_discovery"


def test_current_onboarding_step_uses_feature_discovery_when_provider_ready_and_tour_not_seen() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "in_progress",
            "milestones": {"provider_connected": "2026-03-31T10:00:00Z"},
            "calibration": {"status": "completed"},
            "permissions": {"location": "granted", "notifications": "granted"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "feature_discovery"


def test_current_onboarding_step_uses_completed_when_tour_seen_after_provider_setup() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "dismissed",
            "milestones": {
                "provider_connected": "2026-03-31T10:00:00Z",
                "secondary_tour_seen": "2026-03-31T11:00:00Z",
            },
            "calibration": {"status": "completed"},
            "permissions": {"location": "granted", "notifications": "granted"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "completed"
    assert OnboardingService.is_onboarding_complete(state) is True


def test_current_onboarding_step_uses_completed_when_first_outcome_is_finished_after_provider_setup() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "in_progress",
            "milestones": {
                "provider_connected": "2026-03-31T10:00:00Z",
                "first_outcome_completed": "2026-03-31T11:00:00Z",
            },
            "calibration": {"status": "completed"},
            "permissions": {"location": "granted", "notifications": "granted"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "completed"
    assert OnboardingService.is_onboarding_complete(state) is True


def test_is_onboarding_complete_true_when_tour_seen_even_if_permissions_are_still_skipped() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "dismissed",
            "milestones": {
                "provider_connected": "2026-03-31T10:00:00Z",
                "secondary_tour_seen": "2026-03-31T11:00:00Z",
            },
            "calibration": {"status": "completed"},
            "permissions": {"location": "not_asked", "notifications": "denied"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "completed"
    assert OnboardingService.is_onboarding_complete(state) is True


def test_completed_status_without_completion_milestones_still_requires_signed_in_discovery() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "completed",
            "milestones": {
                "provider_connected": "2026-03-31T10:00:00Z",
            },
            "calibration": {"status": "completed"},
            "permissions": {"location": "granted", "notifications": "granted"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "feature_discovery"
    assert OnboardingService.is_onboarding_complete(state) is False


def test_current_onboarding_step_uses_completed_for_completed_state() -> None:
    state = OnboardingService._resolve_state(
        {
            "status": "completed",
            "milestones": {
                "provider_connected": "2026-03-31T10:00:00Z",
                "secondary_tour_seen": "2026-03-31T11:00:00Z",
            },
            "calibration": {"status": "completed"},
            "permissions": {"location": "granted", "notifications": "granted"},
        }
    )
    state["provider_ready"] = True

    assert OnboardingService.current_onboarding_step(state) == "completed"
