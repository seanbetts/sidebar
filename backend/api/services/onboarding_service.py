"""Service layer for onboarding state management."""

from __future__ import annotations

from typing import Any, cast

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.services.user_settings_service import UserSettingsService

VALID_STATUSES = frozenset({"not_started", "in_progress", "completed", "dismissed"})
VALID_INTENTS = frozenset({"notes", "tasks", "websites", "files", "chat"})
VALID_PERMISSION_STATES = frozenset({"not_asked", "granted", "denied"})
VALID_CALIBRATION_STATUSES = frozenset(
    {"not_started", "in_progress", "awaiting_name_acceptance", "completed"}
)
VALID_CALIBRATION_PROMPTS = frozenset(
    {"primary_goal", "working_relationship", "tone_preferences"}
)
MILESTONE_KEYS = frozenset(
    {
        "provider_connected",
        "first_outcome_completed",
        "profile_basics_set",
        "communication_style_set",
        "secondary_tour_seen",
    }
)
PERMISSION_KEYS = frozenset({"location", "notifications"})
CALIBRATION_ANSWER_KEYS = frozenset(
    {"primary_goal", "working_relationship", "tone_preferences"}
)
_ALLOWED_UPDATE_KEYS = frozenset(
    {"status", "intent", "milestones", "permissions", "last_prompted_at", "calibration"}
)


class OnboardingService:
    """Service for reading and writing per-user onboarding state."""

    @staticmethod
    def is_onboarding_complete(state: dict[str, Any]) -> bool:
        """Return whether onboarding is complete for the resolved state."""
        milestones = state.get("milestones") or {}
        calibration = state.get("calibration") or {}
        has_completion_milestone = bool(
            milestones.get("secondary_tour_seen")
            or milestones.get("first_outcome_completed")
        )
        return (
            has_completion_milestone
            and calibration.get("status") == "completed"
            and not OnboardingService.needs_provider_connection(state)
        )

    @staticmethod
    def needs_provider_connection(state: dict[str, Any]) -> bool:
        """Return whether the user still needs to connect a provider."""
        return not bool(state.get("provider_ready"))

    @staticmethod
    def needs_permission_recovery(state: dict[str, Any]) -> bool:
        """Return whether permission follow-up is the next recovery surface."""
        if OnboardingService.needs_provider_connection(state):
            return False

        permissions = state.get("permissions") or {}
        location = permissions.get("location")
        notifications = permissions.get("notifications")
        return location != "granted" or notifications != "granted"

    @staticmethod
    def needs_feature_discovery(state: dict[str, Any]) -> bool:
        """Return whether the user should enter the signed-in feature tour."""
        return (
            not OnboardingService.is_onboarding_complete(state)
            and not OnboardingService.needs_provider_connection(state)
            and OnboardingService._is_calibration_completed(state)
        )

    @staticmethod
    def _is_calibration_completed(state: dict[str, Any]) -> bool:
        """Return whether calibration has been completed."""
        calibration = state.get("calibration") or {}
        return calibration.get("status") == "completed"

    @staticmethod
    def current_onboarding_step(state: dict[str, Any]) -> str:
        """Return the next onboarding surface for the current state."""
        if OnboardingService.is_onboarding_complete(state):
            return "completed"

        status = state.get("status")
        if status == "not_started" and OnboardingService.needs_provider_connection(
            state
        ):
            return "phase1_wizard"

        if status == "not_started":
            return "soul_calibration"

        if OnboardingService.needs_provider_connection(state):
            return "provider_recovery"

        if not OnboardingService._is_calibration_completed(state):
            return "soul_calibration"

        if OnboardingService.needs_permission_recovery(state):
            return "permission_recovery"

        return "feature_discovery"

    @staticmethod
    def _add_derived_fields(state: dict[str, Any]) -> dict[str, Any]:
        """Return a copy of state with derived onboarding fields included."""
        derived = dict(state)
        derived["is_onboarding_complete"] = OnboardingService.is_onboarding_complete(
            derived
        )
        derived["current_onboarding_step"] = OnboardingService.current_onboarding_step(
            derived
        )
        return derived

    @staticmethod
    def _resolve_state(raw: Any) -> dict[str, Any]:
        """Return canonical onboarding state from stored JSONB, applying defaults.

        Args:
            raw: Raw JSONB value from user_settings.onboarding, or None.

        Returns:
            Canonical state dict with all required keys present.
        """
        if not isinstance(raw, dict):
            raw = {}

        status = raw.get("status")
        if status not in VALID_STATUSES:
            status = "not_started"

        intent = raw.get("intent")
        if intent not in VALID_INTENTS:
            intent = None

        raw_milestones = raw.get("milestones")
        if not isinstance(raw_milestones, dict):
            raw_milestones = {}
        milestones: dict[str, str | None] = {}
        for key in MILESTONE_KEYS:
            value = raw_milestones.get(key)
            milestones[key] = value if isinstance(value, str) else None

        raw_permissions = raw.get("permissions")
        if not isinstance(raw_permissions, dict):
            raw_permissions = {}
        permissions: dict[str, str] = {}
        for key in PERMISSION_KEYS:
            value = raw_permissions.get(key)
            permissions[key] = (
                value if value in VALID_PERMISSION_STATES else "not_asked"
            )

        last_prompted_at = raw.get("last_prompted_at")
        if not isinstance(last_prompted_at, str):
            last_prompted_at = None

        raw_calibration = raw.get("calibration")
        if not isinstance(raw_calibration, dict):
            raw_calibration = {}

        calibration_status = raw_calibration.get("status")
        if calibration_status not in VALID_CALIBRATION_STATUSES:
            calibration_status = "not_started"

        calibration_prompt = raw_calibration.get("current_prompt")
        if calibration_prompt not in VALID_CALIBRATION_PROMPTS:
            calibration_prompt = "primary_goal"

        raw_answers = raw_calibration.get("answers")
        if not isinstance(raw_answers, dict):
            raw_answers = {}
        answers: dict[str, str | None] = {}
        for key in CALIBRATION_ANSWER_KEYS:
            value = raw_answers.get(key)
            answers[key] = value if isinstance(value, str) else None

        proposed_name = raw_calibration.get("proposed_name")
        if not isinstance(proposed_name, str):
            proposed_name = None

        completed_at = raw_calibration.get("completed_at")
        if not isinstance(completed_at, str):
            completed_at = None

        return {
            "status": status,
            "intent": intent,
            "calibration": {
                "status": calibration_status,
                "current_prompt": calibration_prompt,
                "answers": answers,
                "proposed_name": proposed_name,
                "completed_at": completed_at,
            },
            "milestones": milestones,
            "permissions": permissions,
            "last_prompted_at": last_prompted_at,
        }

    @staticmethod
    def _validate_updates(updates: dict[str, Any]) -> None:
        """Raise HTTPException 400 if updates contain invalid fields or values.

        Args:
            updates: Partial update payload from the client.

        Raises:
            HTTPException: 400 for any invalid field name or value.
        """
        unknown = sorted(k for k in updates if k not in _ALLOWED_UPDATE_KEYS)
        if unknown:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid fields: {', '.join(unknown)}",
            )

        if "status" in updates and updates["status"] not in VALID_STATUSES:
            raise HTTPException(status_code=400, detail="Invalid status")

        if (
            "intent" in updates
            and updates["intent"] is not None
            and updates["intent"] not in VALID_INTENTS
        ):
            raise HTTPException(status_code=400, detail="Invalid intent")

        if "milestones" in updates:
            ms = updates["milestones"]
            if not isinstance(ms, dict):
                raise HTTPException(
                    status_code=400, detail="milestones must be an object"
                )
            unknown_ms = sorted(k for k in ms if k not in MILESTONE_KEYS)
            if unknown_ms:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid milestone keys: {', '.join(unknown_ms)}",
                )
            for key, value in ms.items():
                if value is not None and not isinstance(value, str):
                    raise HTTPException(
                        status_code=400,
                        detail=f"Milestone {key} must be a timestamp string or null",
                    )

        if "permissions" in updates:
            perms = updates["permissions"]
            if not isinstance(perms, dict):
                raise HTTPException(
                    status_code=400, detail="permissions must be an object"
                )
            unknown_perms = sorted(k for k in perms if k not in PERMISSION_KEYS)
            if unknown_perms:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid permission keys: {', '.join(unknown_perms)}",
                )
            for key, value in perms.items():
                if value not in VALID_PERMISSION_STATES:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Invalid permission state for {key}",
                    )

        if "calibration" in updates:
            calibration = updates["calibration"]
            if not isinstance(calibration, dict):
                raise HTTPException(
                    status_code=400, detail="calibration must be an object"
                )
            unknown_calibration = sorted(
                key
                for key in calibration
                if key
                not in {
                    "status",
                    "current_prompt",
                    "answers",
                    "proposed_name",
                    "completed_at",
                }
            )
            if unknown_calibration:
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Invalid calibration keys: {', '.join(unknown_calibration)}"
                    ),
                )
            if (
                "status" in calibration
                and calibration["status"] not in VALID_CALIBRATION_STATUSES
            ):
                raise HTTPException(
                    status_code=400, detail="Invalid calibration status"
                )
            if (
                "current_prompt" in calibration
                and calibration["current_prompt"] not in VALID_CALIBRATION_PROMPTS
            ):
                raise HTTPException(
                    status_code=400, detail="Invalid calibration current_prompt"
                )
            if "answers" in calibration:
                answers = calibration["answers"]
                if not isinstance(answers, dict):
                    raise HTTPException(
                        status_code=400, detail="calibration.answers must be an object"
                    )
                unknown_answers = sorted(
                    key for key in answers if key not in CALIBRATION_ANSWER_KEYS
                )
                if unknown_answers:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            "Invalid calibration answer keys: "
                            f"{', '.join(unknown_answers)}"
                        ),
                    )
                for key, value in answers.items():
                    if value is not None and not isinstance(value, str):
                        raise HTTPException(
                            status_code=400,
                            detail=f"Calibration answer {key} must be a string or null",
                        )
            if "proposed_name" in calibration:
                proposed_name = calibration["proposed_name"]
                if proposed_name is not None and not isinstance(proposed_name, str):
                    raise HTTPException(
                        status_code=400,
                        detail="calibration.proposed_name must be a string or null",
                    )
            if "completed_at" in calibration:
                completed_at = calibration["completed_at"]
                if completed_at is not None and not isinstance(completed_at, str):
                    raise HTTPException(
                        status_code=400,
                        detail="calibration.completed_at must be a string or null",
                    )

        if "last_prompted_at" in updates:
            val = updates["last_prompted_at"]
            if val is not None and not isinstance(val, str):
                raise HTTPException(
                    status_code=400,
                    detail="last_prompted_at must be a string or null",
                )

    @staticmethod
    def _compute_provider_ready(db: Session, user_id: str) -> bool:
        """Return True when the user has an active key for their primary provider.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            True if a connected provider key exists.
        """
        from api.services.user_ai_provider_key_service import UserAIProviderKeyService

        settings_record = UserSettingsService.get_settings(db, user_id)
        provider = (
            getattr(settings_record, "ai_primary_provider", None)
            if settings_record
            else None
        )
        if not isinstance(provider, str):
            return False
        provider = provider.strip().lower()

        # Import VALID_AI_PROVIDERS lazily to avoid circular imports
        from api.services.ai.registry import (  # noqa: PLC0415
            VALID_AI_PROVIDERS,
            AIProvider,
        )

        if provider not in VALID_AI_PROVIDERS:
            return False
        record = UserAIProviderKeyService.get_active_record(
            db, user_id, cast(AIProvider, provider)
        )
        return record is not None

    @staticmethod
    def get_onboarding_state(db: Session, user_id: str) -> dict[str, Any]:
        """Return the current onboarding state for a user.

        Reads stored JSONB, applies defaults for any missing keys, and
        computes provider_ready from the live provider-key record.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            Canonical onboarding state dict including provider_ready.
        """
        settings_record = UserSettingsService.get_settings(db, user_id)
        raw = getattr(settings_record, "onboarding", None) if settings_record else None
        state = OnboardingService._resolve_state(raw)
        state["provider_ready"] = OnboardingService._compute_provider_ready(db, user_id)
        return OnboardingService._add_derived_fields(state)

    @staticmethod
    def update_onboarding_state(
        db: Session, user_id: str, updates: dict[str, Any]
    ) -> dict[str, Any]:
        """Apply a partial update to onboarding state and persist it.

        Args:
            db: Database session.
            user_id: Current user ID.
            updates: Partial update payload; only provided keys are changed.

        Returns:
            Updated canonical onboarding state dict including provider_ready.

        Raises:
            HTTPException: 400 for invalid field names or values.
        """
        OnboardingService._validate_updates(updates)

        settings_record = UserSettingsService.get_settings(db, user_id)
        raw = getattr(settings_record, "onboarding", None) if settings_record else None
        current = OnboardingService._resolve_state(raw)

        if "status" in updates:
            current["status"] = updates["status"]
        if "intent" in updates:
            current["intent"] = updates["intent"]
        if "last_prompted_at" in updates:
            current["last_prompted_at"] = updates["last_prompted_at"]
        if "milestones" in updates:
            current["milestones"].update(updates["milestones"])
        if "permissions" in updates:
            current["permissions"].update(updates["permissions"])
        if "calibration" in updates:
            calibration_updates = updates["calibration"]
            current_calibration = current["calibration"]
            if "status" in calibration_updates:
                current_calibration["status"] = calibration_updates["status"]
            if "current_prompt" in calibration_updates:
                current_calibration["current_prompt"] = calibration_updates[
                    "current_prompt"
                ]
            if "answers" in calibration_updates:
                current_calibration["answers"].update(calibration_updates["answers"])
            if "proposed_name" in calibration_updates:
                current_calibration["proposed_name"] = calibration_updates[
                    "proposed_name"
                ]
            if "completed_at" in calibration_updates:
                current_calibration["completed_at"] = calibration_updates[
                    "completed_at"
                ]

        UserSettingsService.upsert_settings(db, user_id, onboarding=current)
        return OnboardingService.get_onboarding_state(db, user_id)
