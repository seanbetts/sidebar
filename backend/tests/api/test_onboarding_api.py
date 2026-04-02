"""Integration tests for GET /api/v1/onboarding and PATCH /api/v1/onboarding."""

import os
from types import SimpleNamespace

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
    assert body["calibration"]["status"] == "not_started"
    assert body["calibration"]["current_prompt"] == "primary_goal"
    assert body["calibration"]["answers"]["primary_goal"] is None
    assert body["calibration"]["answers"]["working_relationship"] is None
    assert body["calibration"]["answers"]["tone_preferences"] is None
    assert body["calibration"]["proposed_name"] is None
    assert body["calibration"]["completed_at"] is None
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


def test_patch_onboarding_updates_calibration_progress(test_client) -> None:
    response = test_client.patch(
        "/api/v1/onboarding",
        headers=_auth_headers(),
        json={
            "calibration": {
                "status": "in_progress",
                "current_prompt": "working_relationship",
                "answers": {"primary_goal": "life_admin"},
            }
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["calibration"]["status"] == "in_progress"
    assert body["calibration"]["current_prompt"] == "working_relationship"
    assert body["calibration"]["answers"]["primary_goal"] == "life_admin"


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


def test_get_onboarding_reports_soul_calibration_for_provider_ready_user_without_calibration(monkeypatch, test_client) -> None:
    from api.services.onboarding_service import OnboardingService

    def fake_get_onboarding_state(*_args, **_kwargs):
        return {
            "status": "dismissed",
            "provider_ready": True,
            "current_onboarding_step": "soul_calibration",
            "is_onboarding_complete": False,
            "intent": None,
            "calibration": {
                "status": "in_progress",
                "current_prompt": "primary_goal",
                "answers": {
                    "primary_goal": None,
                    "working_relationship": None,
                    "tone_preferences": None,
                },
                "proposed_name": None,
                "completed_at": None,
            },
            "milestones": {
                "provider_connected": "2026-03-31T10:00:00Z",
                "first_outcome_completed": None,
                "profile_basics_set": None,
                "communication_style_set": None,
                "secondary_tour_seen": None,
            },
            "permissions": {"location": "granted", "notifications": "granted"},
            "last_prompted_at": None,
        }

    monkeypatch.setattr(OnboardingService, "get_onboarding_state", fake_get_onboarding_state)

    response = test_client.get("/api/v1/onboarding", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["current_onboarding_step"] == "soul_calibration"
    assert body["is_onboarding_complete"] is False
    assert body["calibration"]["current_prompt"] == "primary_goal"


def test_get_onboarding_reports_permission_recovery_for_provider_ready_user_with_missing_permissions(monkeypatch, test_client) -> None:
    from api.services.onboarding_service import OnboardingService

    def fake_get_onboarding_state(*_args, **_kwargs):
        return {
            "status": "dismissed",
            "provider_ready": True,
            "current_onboarding_step": "permission_recovery",
            "is_onboarding_complete": False,
            "intent": None,
            "calibration": {
                "status": "completed",
                "current_prompt": "tone_preferences",
                "answers": {
                    "primary_goal": "life_admin",
                    "working_relationship": "assistant",
                    "tone_preferences": "direct",
                },
                "proposed_name": "Navigator",
                "completed_at": None,
            },
            "milestones": {
                "provider_connected": "2026-03-31T10:00:00Z",
                "first_outcome_completed": None,
                "profile_basics_set": None,
                "communication_style_set": None,
                "secondary_tour_seen": None,
            },
            "permissions": {"location": "denied", "notifications": "granted"},
            "last_prompted_at": None,
        }

    monkeypatch.setattr(OnboardingService, "get_onboarding_state", fake_get_onboarding_state)

    response = test_client.get("/api/v1/onboarding", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["current_onboarding_step"] == "permission_recovery"
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


def test_post_calibration_respond_returns_updated_state(monkeypatch, test_client) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "submit_answer",
        staticmethod(
            lambda *_args, **_kwargs: SimpleNamespace(
                state={
                    "status": "in_progress",
                    "provider_ready": False,
                    "current_onboarding_step": "phase1_wizard",
                    "is_onboarding_complete": False,
                    "intent": None,
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
                    "milestones": {
                        "provider_connected": None,
                        "first_outcome_completed": None,
                        "profile_basics_set": None,
                        "communication_style_set": None,
                        "secondary_tour_seen": None,
                    },
                    "permissions": {
                        "location": "not_asked",
                        "notifications": "not_asked",
                    },
                    "last_prompted_at": None,
                },
                assistant_identity=None,
                assistant_soul=None,
                confirmation_text="What kind of working relationship do you want?",
            )
        ),
    )

    response = test_client.post(
        "/api/v1/onboarding/calibration/respond",
        headers=_auth_headers(),
        json={"prompt": "primary_goal", "answer": "life_admin"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["state"]["calibration"]["answers"]["primary_goal"] == "life_admin"
    assert body["state"]["calibration"]["current_prompt"] == "working_relationship"
    assert body["confirmation_text"] == "What kind of working relationship do you want?"
    assert body["assistant_identity"] is None
    assert body["assistant_soul"] is None


def test_post_calibration_name_regenerate_returns_generated_name(
    monkeypatch,
    test_client,
) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "regenerate_name",
        staticmethod(
            lambda *_args, **_kwargs: SimpleNamespace(
                state={
                    "status": "in_progress",
                    "provider_ready": False,
                    "current_onboarding_step": "phase1_wizard",
                    "is_onboarding_complete": False,
                    "intent": None,
                    "calibration": {
                        "status": "awaiting_name_acceptance",
                        "current_prompt": "tone_preferences",
                        "answers": {
                            "primary_goal": "life_admin",
                            "working_relationship": "collaborative",
                            "tone_preferences": "direct_but_kind",
                        },
                        "proposed_name": "Compass",
                        "completed_at": None,
                    },
                    "milestones": {
                        "provider_connected": None,
                        "first_outcome_completed": None,
                        "profile_basics_set": None,
                        "communication_style_set": None,
                        "secondary_tour_seen": None,
                    },
                    "permissions": {
                        "location": "not_asked",
                        "notifications": "not_asked",
                    },
                    "last_prompted_at": None,
                },
                assistant_identity={"name": "Compass"},
                assistant_soul=None,
                confirmation_text="How about Compass?",
            )
        ),
    )

    response = test_client.post(
        "/api/v1/onboarding/calibration/name/regenerate",
        headers=_auth_headers(),
        json={},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["state"]["calibration"]["proposed_name"] == "Compass"
    assert body["assistant_identity"]["name"] == "Compass"
    assert body["assistant_soul"] is None


def test_post_calibration_name_accept_marks_completed(monkeypatch, test_client) -> None:
    from api.services.onboarding_calibration_service import OnboardingCalibrationService

    monkeypatch.setattr(
        OnboardingCalibrationService,
        "accept_name",
        staticmethod(
            lambda *_args, **_kwargs: SimpleNamespace(
                state={
                    "status": "in_progress",
                    "provider_ready": False,
                    "current_onboarding_step": "phase1_wizard",
                    "is_onboarding_complete": False,
                    "intent": None,
                    "calibration": {
                        "status": "completed",
                        "current_prompt": "tone_preferences",
                        "answers": {
                            "primary_goal": "life_admin",
                            "working_relationship": "collaborative",
                            "tone_preferences": "direct_but_kind",
                        },
                        "proposed_name": "Navigator",
                        "completed_at": "2026-04-02T10:00:00Z",
                    },
                    "milestones": {
                        "provider_connected": None,
                        "first_outcome_completed": None,
                        "profile_basics_set": None,
                        "communication_style_set": None,
                        "secondary_tour_seen": None,
                    },
                    "permissions": {
                        "location": "not_asked",
                        "notifications": "not_asked",
                    },
                    "last_prompted_at": None,
                },
                assistant_identity=None,
                assistant_soul=None,
                confirmation_text="Navigator is locked in.",
            )
        ),
    )

    response = test_client.post(
        "/api/v1/onboarding/calibration/name/accept",
        headers=_auth_headers(),
        json={},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["state"]["calibration"]["status"] == "completed"
    assert body["state"]["calibration"]["completed_at"] == "2026-04-02T10:00:00Z"
    assert body["confirmation_text"] == "Navigator is locked in."
