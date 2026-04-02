"""Integration tests for GET /api/v1/onboarding and PATCH /api/v1/onboarding."""

import os

import pytest

from api.config import settings

TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


# ---------------------------------------------------------------------------
# GET /api/v1/onboarding
# ---------------------------------------------------------------------------

def test_get_onboarding_returns_defaults_for_new_user(test_client) -> None:
    response = test_client.get("/api/v1/onboarding", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "not_started"
    assert body["provider_ready"] is False
    assert body["current_onboarding_step"] == "phase1_wizard"
    assert body["is_onboarding_complete"] is False
    assert body["intent"] is None
    assert body["milestones"]["provider_connected"] is None
    assert body["milestones"]["first_outcome_completed"] is None
    assert body["permissions"]["location"] == "not_asked"
    assert body["permissions"]["notifications"] == "not_asked"
    assert body["last_prompted_at"] is None


def test_get_onboarding_requires_auth(test_client) -> None:
    response = test_client.get("/api/v1/onboarding")
    assert response.status_code == 401


# ---------------------------------------------------------------------------
# PATCH /api/v1/onboarding
# ---------------------------------------------------------------------------

def test_patch_onboarding_updates_status(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"status": "in_progress"},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "in_progress"


def test_patch_onboarding_updates_intent(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"intent": "notes"},
    )
    assert response.status_code == 200
    assert response.json()["intent"] == "notes"


def test_patch_onboarding_updates_milestone(test_client) -> None:
    ts = "2026-03-13T10:00:00Z"
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"milestones": {"provider_connected": ts}},
    )
    assert response.status_code == 200
    assert response.json()["milestones"]["provider_connected"] == ts


def test_patch_onboarding_updates_permission(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"permissions": {"location": "granted"}},
    )
    assert response.status_code == 200
    assert response.json()["permissions"]["location"] == "granted"


def test_patch_onboarding_persists_across_requests(test_client) -> None:
    test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"status": "in_progress", "intent": "tasks"},
    )
    response = test_client.get("/api/v1/onboarding", headers=_auth_headers())
    body = response.json()
    assert body["status"] == "in_progress"
    assert body["intent"] == "tasks"


def test_get_onboarding_does_not_treat_completed_status_as_finished_without_completion_milestones(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"status": "completed"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["current_onboarding_step"] == "provider_recovery"
    assert body["is_onboarding_complete"] is False


def test_patch_onboarding_merges_milestones(test_client) -> None:
    ts1 = "2026-03-13T10:00:00Z"
    ts2 = "2026-03-13T11:00:00Z"
    test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"milestones": {"provider_connected": ts1}},
    )
    test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"milestones": {"first_outcome_completed": ts2}},
    )
    response = test_client.get("/api/v1/onboarding", headers=_auth_headers())
    milestones = response.json()["milestones"]
    assert milestones["provider_connected"] == ts1
    assert milestones["first_outcome_completed"] == ts2


def test_patch_onboarding_rejects_invalid_status(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"status": "bogus"},
    )
    assert response.status_code == 400


def test_patch_onboarding_rejects_invalid_intent(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"intent": "bogus"},
    )
    assert response.status_code == 400


def test_patch_onboarding_rejects_unknown_fields(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={"unknown_field": "value"},
    )
    assert response.status_code == 422


def test_patch_onboarding_requires_auth(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        json={"status": "in_progress"},
    )
    assert response.status_code == 401
