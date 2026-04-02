"""State machine for onboarding soul calibration."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.services.agent_settings_service import AgentSettingsService
from api.services.onboarding_service import VALID_CALIBRATION_PROMPTS, OnboardingService

PROMPT_SEQUENCE = ("primary_goal", "working_relationship", "tone_preferences")
NEXT_PROMPT = {
    "primary_goal": "working_relationship",
    "working_relationship": "tone_preferences",
}
GENERATION_RETRY_LIMIT = 2


@dataclass(slots=True)
class CalibrationActionResult:
    """Structured result for calibration state transitions."""

    state: dict[str, Any]
    assistant_identity: dict[str, Any] | None = None
    assistant_soul: dict[str, Any] | None = None
    confirmation_text: str | None = None


class OnboardingCalibrationService:
    """Manage onboarding calibration prompts and generated assistant settings."""

    @staticmethod
    def submit_answer(
        db: Session,
        user_id: str,
        prompt: str,
        answer: str,
    ) -> CalibrationActionResult:
        """Persist a prompt answer and advance the calibration state."""
        normalized_prompt = OnboardingCalibrationService._normalize_prompt(prompt)
        normalized_answer = OnboardingCalibrationService._normalize_answer(answer)
        state = OnboardingService.get_onboarding_state(db, user_id)
        OnboardingCalibrationService._require_provider_ready(state)
        calibration = state["calibration"]
        OnboardingCalibrationService._assert_prompt_is_actionable(
            calibration,
            expected_prompt=normalized_prompt,
        )

        next_onboarding = OnboardingService._resolve_state(state)
        next_calibration = next_onboarding["calibration"]
        next_calibration["answers"][normalized_prompt] = normalized_answer
        next_onboarding["status"] = "in_progress"

        if normalized_prompt != "tone_preferences":
            next_calibration["status"] = "in_progress"
            next_calibration["current_prompt"] = NEXT_PROMPT[normalized_prompt]
            OnboardingService.update_onboarding_state(
                db,
                user_id,
                {
                    "status": next_onboarding["status"],
                    "calibration": next_calibration,
                },
            )
            return CalibrationActionResult(
                state=OnboardingCalibrationService._build_state_response(
                    next_onboarding,
                    provider_ready=bool(state.get("provider_ready")),
                ),
                confirmation_text=OnboardingCalibrationService._prompt_confirmation(
                    next_calibration["current_prompt"]
                ),
            )

        # Persist the final answer before generation so resume can retry from tone.
        next_calibration["status"] = "in_progress"
        next_calibration["current_prompt"] = "tone_preferences"
        OnboardingService.update_onboarding_state(
            db,
            user_id,
            {
                "status": next_onboarding["status"],
                "calibration": next_calibration,
            },
        )
        generated = OnboardingCalibrationService._generate_validated_payload(
            db,
            user_id,
            answers=next_calibration["answers"],
            previous_name=next_calibration.get("proposed_name"),
        )
        next_calibration["status"] = "awaiting_name_acceptance"
        next_calibration["proposed_name"] = generated["assistant_identity"]["name"]

        settings_payload = AgentSettingsService.update_with_onboarding(
            db,
            user_id,
            {
                "assistant_identity": generated["assistant_identity"],
                "assistant_soul": generated["assistant_soul"],
            },
            onboarding=next_onboarding,
            reason="Initial soul calibration bootstrap.",
        )
        return CalibrationActionResult(
            state=OnboardingCalibrationService._build_state_response(
                next_onboarding,
                provider_ready=bool(state.get("provider_ready")),
            ),
            assistant_identity=settings_payload["assistant_identity"],
            assistant_soul=settings_payload["assistant_soul"],
            confirmation_text=generated["confirmation_text"],
        )

    @staticmethod
    def regenerate_name(db: Session, user_id: str) -> CalibrationActionResult:
        """Generate a replacement assistant name while preserving other fields."""
        state = OnboardingService.get_onboarding_state(db, user_id)
        OnboardingCalibrationService._require_provider_ready(state)
        calibration = state["calibration"]
        if calibration.get("status") != "awaiting_name_acceptance":
            raise HTTPException(
                status_code=409,
                detail="Calibration is not awaiting name acceptance",
            )

        answers = calibration.get("answers") or {}
        previous_name = calibration.get("proposed_name")
        next_name = OnboardingCalibrationService._generate_validated_name(
            db,
            user_id,
            answers=answers,
            previous_name=previous_name,
        )

        next_onboarding = OnboardingService._resolve_state(state)
        next_onboarding["calibration"]["proposed_name"] = next_name
        settings_payload = AgentSettingsService.update_with_onboarding(
            db,
            user_id,
            {"assistant_identity": {"name": next_name}},
            onboarding=next_onboarding,
            reason="Regenerated calibration assistant name.",
        )
        return CalibrationActionResult(
            state=OnboardingCalibrationService._build_state_response(
                next_onboarding,
                provider_ready=bool(state.get("provider_ready")),
            ),
            assistant_identity=settings_payload["assistant_identity"],
            confirmation_text=f"How about {next_name}?",
        )

    @staticmethod
    def accept_name(db: Session, user_id: str) -> CalibrationActionResult:
        """Finalize calibration after the user accepts the proposed name."""
        state = OnboardingService.get_onboarding_state(db, user_id)
        OnboardingCalibrationService._require_provider_ready(state)
        calibration = state["calibration"]
        if calibration.get("status") != "awaiting_name_acceptance":
            raise HTTPException(
                status_code=409,
                detail="Calibration is not awaiting name acceptance",
            )
        proposed_name = calibration.get("proposed_name")
        if not isinstance(proposed_name, str) or not proposed_name.strip():
            raise HTTPException(
                status_code=409,
                detail="Calibration cannot complete without a proposed name",
            )

        next_onboarding = OnboardingService._resolve_state(state)
        next_onboarding["status"] = "in_progress"
        next_onboarding["calibration"]["status"] = "completed"
        next_onboarding["calibration"]["completed_at"] = (
            datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        )
        OnboardingService.update_onboarding_state(
            db,
            user_id,
            {
                "status": next_onboarding["status"],
                "calibration": next_onboarding["calibration"],
            },
        )
        return CalibrationActionResult(
            state=OnboardingCalibrationService._build_state_response(
                next_onboarding,
                provider_ready=bool(state.get("provider_ready")),
            ),
            confirmation_text=f"{proposed_name.strip()} is locked in.",
        )

    @staticmethod
    def _normalize_prompt(prompt: Any) -> str:
        """Validate the requested prompt identifier."""
        if not isinstance(prompt, str):
            raise HTTPException(status_code=400, detail="prompt must be a string")
        normalized = prompt.strip()
        if normalized not in VALID_CALIBRATION_PROMPTS:
            raise HTTPException(status_code=400, detail="Invalid calibration prompt")
        return normalized

    @staticmethod
    def _normalize_answer(answer: Any) -> str:
        """Validate and normalize an answer string."""
        if not isinstance(answer, str):
            raise HTTPException(status_code=400, detail="answer must be a string")
        normalized = answer.strip()
        if not normalized:
            raise HTTPException(status_code=400, detail="answer must not be blank")
        return normalized

    @staticmethod
    def _assert_prompt_is_actionable(
        calibration: dict[str, Any],
        *,
        expected_prompt: str,
    ) -> None:
        """Ensure the requested prompt matches the current calibration step."""
        status = calibration.get("status")
        if status in {"awaiting_name_acceptance", "completed"}:
            raise HTTPException(
                status_code=409,
                detail="Calibration is not accepting prompt answers",
            )
        current_prompt = calibration.get("current_prompt") or PROMPT_SEQUENCE[0]
        if current_prompt != expected_prompt:
            raise HTTPException(
                status_code=409,
                detail=f"Expected prompt {current_prompt}",
            )

    @staticmethod
    def _prompt_confirmation(next_prompt: str) -> str:
        """Return a stable assistant confirmation string for the next prompt."""
        if next_prompt == "working_relationship":
            return "What kind of working relationship do you want?"
        if next_prompt == "tone_preferences":
            return "How should I sound when we work together?"
        return "Tell me more about what you need."

    @staticmethod
    def _generate_validated_payload(
        db: Session,
        user_id: str,
        *,
        answers: dict[str, Any],
        previous_name: str | None,
    ) -> dict[str, Any]:
        """Generate assistant soul and identity, retrying once on validation errors."""
        last_error: HTTPException | None = None
        for attempt in range(GENERATION_RETRY_LIMIT):
            generated = OnboardingCalibrationService._generate_calibration_payload(
                answers=answers,
                previous_name=previous_name,
                repair_mode=attempt > 0,
                validation_error=last_error,
            )
            try:
                prepared = AgentSettingsService.prepare_agent_updates(
                    db,
                    user_id,
                    {
                        "assistant_identity": generated["assistant_identity"],
                        "assistant_soul": generated["assistant_soul"],
                    },
                    reason="Initial soul calibration bootstrap.",
                )
            except HTTPException as exc:
                if exc.status_code != 400:
                    raise
                last_error = exc
                previous_name = OnboardingCalibrationService._repair_previous_name(
                    generated,
                    previous_name=previous_name,
                )
                continue

            identity = prepared.get("assistant_identity") or {}
            soul = prepared.get("assistant_soul") or {}
            identity.pop("_meta", None)
            soul.pop("_meta", None)
            return {
                "assistant_identity": identity,
                "assistant_soul": soul,
                "confirmation_text": generated.get("confirmation_text")
                or f'{identity.get("name", "sideBar")} is ready for review.',
            }

        raise HTTPException(
            status_code=503,
            detail=("Calibration generation failed validation twice. " "Please retry."),
        ) from last_error

    @staticmethod
    def _generate_validated_name(
        db: Session,
        user_id: str,
        *,
        answers: dict[str, Any],
        previous_name: str | None,
    ) -> str:
        """Generate a name candidate and validate it through the agent update path."""
        last_error: HTTPException | None = None
        for _ in range(GENERATION_RETRY_LIMIT):
            candidate = OnboardingCalibrationService._generate_name_candidate(
                answers=answers,
                previous_name=previous_name,
            )
            try:
                prepared = AgentSettingsService.prepare_agent_updates(
                    db,
                    user_id,
                    {"assistant_identity": {"name": candidate}},
                    reason="Regenerated calibration assistant name.",
                )
            except HTTPException as exc:
                if exc.status_code != 400:
                    raise
                last_error = exc
                previous_name = candidate
                continue

            assistant_identity = prepared.get("assistant_identity") or {}
            assistant_identity.pop("_meta", None)
            return str(assistant_identity.get("name") or candidate)

        raise HTTPException(
            status_code=503,
            detail="Calibration name generation failed validation twice. Please retry.",
        ) from last_error

    @staticmethod
    def _generate_calibration_payload(
        *,
        answers: dict[str, Any],
        previous_name: str | None = None,
        repair_mode: bool = False,
        validation_error: HTTPException | None = None,
    ) -> dict[str, Any]:
        """Build a constrained assistant identity and soul from calibration answers."""
        primary_goal = str(answers.get("primary_goal") or "meaningful progress").strip()
        working_relationship = str(
            answers.get("working_relationship") or "a collaborative working style"
        ).strip()
        tone_preferences = str(
            answers.get("tone_preferences") or "direct and calm"
        ).strip()
        name = OnboardingCalibrationService._generate_name_candidate(
            answers=answers,
            previous_name=previous_name,
        )
        if repair_mode:
            name = OnboardingCalibrationService._repair_name_candidate(
                name,
                validation_error=validation_error,
            )
        return {
            "assistant_identity": {
                "name": name,
                "tone": f"{tone_preferences.capitalize()}.",
                "values": "Clarity, pragmatism, and steady follow-through.",
                "boundaries": (
                    "Never invent facts, keep user agency intact, and stay grounded "
                    "in the user's stated goals."
                ),
            },
            "assistant_soul": {
                "purpose": (f"Help the user make durable progress on {primary_goal}."),
                "operating_principles": (
                    f"Work like {working_relationship}, keep momentum visible, "
                    "and reduce cognitive load."
                ),
                "adaptation_policy": (
                    "Adapt to durable preferences captured during calibration, "
                    "not one-off wording."
                ),
                "success_signals": (
                    "The user feels understood, needs fewer clarifications, "
                    "and finishes more of the work they intended to do."
                ),
            },
            "confirmation_text": f"{name} is ready for review.",
        }

    @staticmethod
    def _generate_name_candidate(
        *,
        answers: dict[str, Any],
        previous_name: str | None = None,
    ) -> str:
        """Select a constrained assistant name candidate from a small fixed pool."""
        primary_goal = str(answers.get("primary_goal") or "").strip().lower()
        if "admin" in primary_goal or "life" in primary_goal:
            candidates = ("Navigator", "Compass", "Harbor", "Anchor")
        elif "creative" in primary_goal or "write" in primary_goal:
            candidates = ("Ink", "Studio", "Signal", "Draft")
        else:
            candidates = ("Navigator", "Compass", "Harbor", "Signal")

        if previous_name in candidates:
            index = candidates.index(previous_name)
            return candidates[(index + 1) % len(candidates)]
        return candidates[0]

    @staticmethod
    def _require_provider_ready(state: dict[str, Any]) -> None:
        """Reject calibration actions until the user has a connected provider."""
        if not bool(state.get("provider_ready")):
            raise HTTPException(
                status_code=409,
                detail=(
                    "Provider connection is required before calibration " "can continue"
                ),
            )

    @staticmethod
    def _build_state_response(
        onboarding_state: dict[str, Any],
        *,
        provider_ready: bool,
    ) -> dict[str, Any]:
        """Attach provider state and derived fields to an onboarding payload."""
        resolved = OnboardingService._resolve_state(onboarding_state)
        resolved["provider_ready"] = provider_ready
        return OnboardingService._add_derived_fields(resolved)

    @staticmethod
    def _repair_previous_name(
        generated: dict[str, Any],
        *,
        previous_name: str | None,
    ) -> str | None:
        """Extract the last attempted generated name for a stricter retry."""
        assistant_identity = generated.get("assistant_identity")
        if not isinstance(assistant_identity, dict):
            return previous_name
        candidate = assistant_identity.get("name")
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
        return previous_name

    @staticmethod
    def _repair_name_candidate(
        candidate: str,
        *,
        validation_error: HTTPException | None,
    ) -> str:
        """Return a stricter repaired name candidate after validation fails."""
        if validation_error and "assistant_identity.name exceeds" in str(
            validation_error.detail
        ):
            trimmed = candidate.strip()[:120]
            return trimmed or "Navigator"
        return candidate.strip() or "Navigator"
