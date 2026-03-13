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
    assert state["milestones"]["provider_connected"] is None
    assert state["milestones"]["first_outcome_completed"] is None
    assert state["permissions"]["location"] == "not_asked"
    assert state["permissions"]["notifications"] == "not_asked"
    assert state["last_prompted_at"] is None


def test_resolve_state_preserves_valid_values() -> None:
    raw = {
        "status": "in_progress",
        "intent": "notes",
        "milestones": {"provider_connected": "2026-03-13T10:00:00Z"},
        "permissions": {"location": "granted", "notifications": "denied"},
        "last_prompted_at": "2026-03-13T09:00:00Z",
    }
    state = OnboardingService._resolve_state(raw)
    assert state["status"] == "in_progress"
    assert state["intent"] == "notes"
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
            "milestones": {"provider_connected": "2026-03-13T10:00:00Z"},
            "permissions": {"location": "granted"},
        }
    )


def test_validate_updates_accepts_null_intent() -> None:
    OnboardingService._validate_updates({"intent": None})


def test_validate_updates_accepts_null_milestone() -> None:
    OnboardingService._validate_updates({"milestones": {"provider_connected": None}})
