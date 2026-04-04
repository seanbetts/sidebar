"""State machine for onboarding soul calibration."""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from datetime import UTC, datetime
from types import SimpleNamespace
from typing import Any, cast

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.config import settings
from api.services.agent.prompt.templates import (
    CALIBRATION_PROMPT_ASSISTANT_IDENTITY_BOUNDARIES,
    CALIBRATION_PROMPT_ASSISTANT_IDENTITY_NAME,
    CALIBRATION_PROMPT_ASSISTANT_IDENTITY_TONE,
    CALIBRATION_PROMPT_ASSISTANT_IDENTITY_VALUES,
    CALIBRATION_PROMPT_ASSISTANT_SOUL_ADAPTATION_POLICY,
    CALIBRATION_PROMPT_ASSISTANT_SOUL_OPERATING_PRINCIPLES,
    CALIBRATION_PROMPT_ASSISTANT_SOUL_PURPOSE,
    CALIBRATION_PROMPT_ASSISTANT_SOUL_SUCCESS_SIGNALS,
)
from api.services.agent_settings_service import AgentSettingsService
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.policy import AIPolicyService
from api.services.ai.registry import AIProvider
from api.services.onboarding_calibration_prompting import (
    is_rejected_name,
    normalized_rejected_names,
    render_calibration_field_prompt,
)
from api.services.onboarding_service import VALID_CALIBRATION_PROMPTS, OnboardingService
from api.services.settings_service import SettingsService
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.user_settings_service import UserSettingsService

PROMPT_SEQUENCE = ("primary_goal", "working_relationship", "tone_preferences")
NEXT_PROMPT = {
    "primary_goal": "working_relationship",
    "working_relationship": "tone_preferences",
}
PROMPT_INDEX = {prompt: index for index, prompt in enumerate(PROMPT_SEQUENCE)}
GENERATION_RETRY_LIMIT = 2
GENERATION_REASON = "Authored during soul calibration."
NAME_REGENERATION_REASON = "Regenerated during soul calibration."

STAGE_FIELDS: dict[str, tuple[tuple[str, str], ...]] = {
    "primary_goal": (("assistant_soul", "purpose"),),
    "working_relationship": (
        ("assistant_soul", "success_signals"),
        ("assistant_soul", "operating_principles"),
        ("assistant_soul", "adaptation_policy"),
    ),
    "tone_preferences": (
        ("assistant_identity", "tone"),
        ("assistant_identity", "values"),
        ("assistant_identity", "boundaries"),
    ),
}
FIELD_MAX_OUTPUT_TOKENS: dict[tuple[str, str], int] = {
    ("assistant_identity", "name"): 48,
    ("assistant_identity", "tone"): 220,
    ("assistant_identity", "values"): 260,
    ("assistant_identity", "boundaries"): 280,
    ("assistant_soul", "purpose"): 220,
    ("assistant_soul", "success_signals"): 320,
    ("assistant_soul", "operating_principles"): 320,
    ("assistant_soul", "adaptation_policy"): 280,
}
FIELD_TEMPERATURES: dict[tuple[str, str], float] = {
    ("assistant_identity", "name"): 0.8,
    ("assistant_identity", "tone"): 0.65,
    ("assistant_identity", "values"): 0.65,
    ("assistant_identity", "boundaries"): 0.65,
    ("assistant_soul", "purpose"): 0.65,
    ("assistant_soul", "success_signals"): 0.65,
    ("assistant_soul", "operating_principles"): 0.65,
    ("assistant_soul", "adaptation_policy"): 0.65,
}
FIELD_PROMPT_TEMPLATES: dict[tuple[str, str], str] = {
    ("assistant_soul", "purpose"): CALIBRATION_PROMPT_ASSISTANT_SOUL_PURPOSE,
    (
        "assistant_soul",
        "success_signals",
    ): CALIBRATION_PROMPT_ASSISTANT_SOUL_SUCCESS_SIGNALS,
    (
        "assistant_soul",
        "operating_principles",
    ): CALIBRATION_PROMPT_ASSISTANT_SOUL_OPERATING_PRINCIPLES,
    (
        "assistant_soul",
        "adaptation_policy",
    ): CALIBRATION_PROMPT_ASSISTANT_SOUL_ADAPTATION_POLICY,
    ("assistant_identity", "tone"): CALIBRATION_PROMPT_ASSISTANT_IDENTITY_TONE,
    ("assistant_identity", "values"): CALIBRATION_PROMPT_ASSISTANT_IDENTITY_VALUES,
    (
        "assistant_identity",
        "boundaries",
    ): CALIBRATION_PROMPT_ASSISTANT_IDENTITY_BOUNDARIES,
    ("assistant_identity", "name"): CALIBRATION_PROMPT_ASSISTANT_IDENTITY_NAME,
}


@dataclass(slots=True)
class CalibrationActionResult:
    """Structured result for calibration state transitions."""

    state: dict[str, Any]
    assistant_identity: dict[str, Any] | None = None
    assistant_soul: dict[str, Any] | None = None
    confirmation_text: str | None = None


@dataclass(slots=True)
class GenerationContext:
    """Immutable context required for stage field generation."""

    settings_snapshot: Any
    current_identity: dict[str, Any]
    current_soul: dict[str, Any]
    provider_keys: dict[AIProvider, str | None]


class OnboardingCalibrationService:
    """Manage onboarding calibration prompts and generated assistant settings."""

    @staticmethod
    def submit_answer(
        db: Session,
        user_id: str,
        prompt: str,
        answer: str,
    ) -> CalibrationActionResult:
        """Persist a prompt answer, generate authored settings, and advance state."""
        normalized_prompt = OnboardingCalibrationService._normalize_prompt(prompt)
        normalized_answer = OnboardingCalibrationService._normalize_answer(answer)
        state = OnboardingService.get_onboarding_state(db, user_id)
        OnboardingCalibrationService._require_provider_ready(state)
        calibration = state["calibration"]
        prior_proposed_name = calibration.get("proposed_name")
        OnboardingCalibrationService._assert_prompt_is_actionable(
            calibration,
            expected_prompt=normalized_prompt,
        )

        next_onboarding = OnboardingService._resolve_state(state)
        next_calibration = next_onboarding["calibration"]
        OnboardingCalibrationService._reset_dependent_state(
            next_calibration,
            answered_prompt=normalized_prompt,
        )
        next_calibration["answers"][normalized_prompt] = normalized_answer
        next_onboarding["status"] = "in_progress"

        # Persist the latest answer before generation so retries can resume cleanly.
        OnboardingService.update_onboarding_state(
            db,
            user_id,
            {
                "status": next_onboarding["status"],
                "calibration": next_calibration,
            },
        )

        stage_updates = OnboardingCalibrationService._generate_stage_updates(
            db,
            user_id,
            answered_prompt=normalized_prompt,
            answers=next_calibration["answers"],
            previous_name=prior_proposed_name,
        )
        if normalized_prompt == "tone_preferences":
            next_calibration["status"] = "awaiting_name_acceptance"
            next_calibration["proposed_name"] = None
            next_calibration["current_prompt"] = "tone_preferences"
        else:
            next_calibration["status"] = "in_progress"
            next_calibration["current_prompt"] = NEXT_PROMPT[normalized_prompt]

        settings_payload: dict[str, Any] | None = None
        if stage_updates:
            settings_payload = AgentSettingsService.update_with_onboarding(
                db,
                user_id,
                stage_updates,
                onboarding=next_onboarding,
                reason=GENERATION_REASON,
            )
        elif normalized_prompt == "tone_preferences":
            OnboardingService.update_onboarding_state(
                db,
                user_id,
                {
                    "status": next_onboarding["status"],
                    "calibration": next_calibration,
                },
            )

        assistant_identity_payload = (
            settings_payload["assistant_identity"]
            if settings_payload and "assistant_identity" in stage_updates
            else None
        )
        assistant_soul_payload = (
            settings_payload["assistant_soul"]
            if settings_payload and "assistant_soul" in stage_updates
            else None
        )

        return CalibrationActionResult(
            state=OnboardingCalibrationService._build_state_response(
                next_onboarding,
                provider_ready=bool(state.get("provider_ready")),
            ),
            assistant_identity=assistant_identity_payload,
            assistant_soul=assistant_soul_payload,
            confirmation_text=(
                "Choosing a name."
                if normalized_prompt == "tone_preferences"
                else OnboardingCalibrationService._prompt_confirmation(
                    next_calibration["current_prompt"]
                )
            ),
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
        rejected_names = normalized_rejected_names(
            rejected_names=calibration.get("rejected_names"),
            previous_name=previous_name,
        )
        next_name_update = (
            OnboardingCalibrationService._generate_validated_field_update(
                db,
                user_id,
                scope="assistant_identity",
                field_name="name",
                answers=answers,
                previous_name=previous_name,
                rejected_names=rejected_names,
            )
        )
        next_name = (
            (next_name_update.get("assistant_identity") or {}).get("name")
        ) or ""

        next_onboarding = OnboardingService._resolve_state(state)
        next_onboarding["calibration"]["rejected_names"] = rejected_names
        next_onboarding["calibration"]["proposed_name"] = next_name
        settings_payload = AgentSettingsService.update_with_onboarding(
            db,
            user_id,
            next_name_update,
            onboarding=next_onboarding,
            reason=NAME_REGENERATION_REASON,
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
        """Ensure the requested prompt is current or earlier in the calibration flow."""
        status = calibration.get("status")
        if status == "completed":
            raise HTTPException(
                status_code=409,
                detail="Calibration is not accepting prompt answers",
            )
        current_prompt = calibration.get("current_prompt") or PROMPT_SEQUENCE[0]
        if status == "awaiting_name_acceptance":
            if expected_prompt not in PROMPT_INDEX:
                raise HTTPException(
                    status_code=409,
                    detail="Calibration is not accepting prompt answers",
                )
            return
        if PROMPT_INDEX[expected_prompt] > PROMPT_INDEX[current_prompt]:
            raise HTTPException(
                status_code=409,
                detail=f"Expected prompt {current_prompt}",
            )

    @staticmethod
    def _reset_dependent_state(
        calibration: dict[str, Any],
        *,
        answered_prompt: str,
    ) -> None:
        """Clear any downstream answers that must be regenerated after an edit."""
        answers = calibration.get("answers") or {}
        calibration["answers"] = answers

        if answered_prompt == "primary_goal":
            answers["working_relationship"] = None
            answers["tone_preferences"] = None
            calibration["current_prompt"] = "working_relationship"
            calibration["status"] = "in_progress"
            calibration["proposed_name"] = None
            calibration["rejected_names"] = []
            calibration["completed_at"] = None
            return

        if answered_prompt == "working_relationship":
            answers["tone_preferences"] = None
            calibration["current_prompt"] = "tone_preferences"
            calibration["status"] = "in_progress"
            calibration["proposed_name"] = None
            calibration["rejected_names"] = []
            calibration["completed_at"] = None
            return

        calibration["current_prompt"] = "tone_preferences"
        calibration["status"] = "in_progress"
        calibration["proposed_name"] = None
        calibration["rejected_names"] = []
        calibration["completed_at"] = None

    @staticmethod
    def _prompt_confirmation(next_prompt: str) -> str:
        """Return a stable assistant confirmation string for the next prompt."""
        if next_prompt == "working_relationship":
            return "How should I work with you?"
        if next_prompt == "tone_preferences":
            return "How should I sound?"
        return "Tell me more about what you need."

    @staticmethod
    def _generate_stage_updates(
        db: Session,
        user_id: str,
        *,
        answered_prompt: str,
        answers: dict[str, Any],
        previous_name: str | None,
    ) -> dict[str, Any]:
        """Generate and merge all assistant settings owned by this stage."""
        generation_context = OnboardingCalibrationService._build_generation_context(
            db,
            user_id,
        )
        combined: dict[str, Any] = {}

        stage_fields = STAGE_FIELDS.get(answered_prompt, ())
        if stage_fields:
            stage_updates = asyncio.run(
                OnboardingCalibrationService._generate_parallel_stage_fields(
                    generation_context=generation_context,
                    stage_fields=stage_fields,
                    answers=answers,
                )
            )
            for update in stage_updates:
                OnboardingCalibrationService._merge_generated_updates(combined, update)

        return combined

    @staticmethod
    def _generate_validated_field_update(
        db: Session,
        user_id: str,
        *,
        scope: str,
        field_name: str,
        answers: dict[str, Any],
        previous_name: str | None,
        rejected_names: list[str] | None = None,
    ) -> dict[str, dict[str, str]]:
        """Generate, validate, and normalize a single assistant settings field."""
        generation_context = OnboardingCalibrationService._build_generation_context(
            db,
            user_id,
        )
        return (
            OnboardingCalibrationService._generate_validated_field_update_for_context(
                db,
                user_id,
                scope=scope,
                field_name=field_name,
                answers=answers,
                previous_name=previous_name,
                rejected_names=rejected_names,
                generation_context=generation_context,
                current_identity=generation_context.current_identity,
                current_soul=generation_context.current_soul,
            )
        )

    @staticmethod
    async def _generate_parallel_stage_fields(
        *,
        generation_context: GenerationContext,
        stage_fields: tuple[tuple[str, str], ...],
        answers: dict[str, Any],
    ) -> list[dict[str, dict[str, str]]]:
        """Generate independent stage-owned fields concurrently."""
        tasks = [
            asyncio.to_thread(
                OnboardingCalibrationService._generate_validated_field_update_for_context,
                None,
                None,
                scope=scope,
                field_name=field_name,
                answers=answers,
                previous_name=None,
                rejected_names=None,
                generation_context=generation_context,
                current_identity=generation_context.current_identity,
                current_soul=generation_context.current_soul,
            )
            for scope, field_name in stage_fields
        ]
        return list(await asyncio.gather(*tasks))

    @staticmethod
    def _generate_validated_field_update_for_context(
        db: Session | None,
        user_id: str | None,
        *,
        scope: str,
        field_name: str,
        answers: dict[str, Any],
        previous_name: str | None,
        rejected_names: list[str] | None,
        generation_context: GenerationContext,
        current_identity: dict[str, Any],
        current_soul: dict[str, Any],
    ) -> dict[str, dict[str, str]]:
        """Generate, validate, and normalize a field from a frozen snapshot."""
        request_db = db
        request_user_id = user_id
        if request_db is None or request_user_id is None:
            request_db = cast(Session, object())
            request_user_id = "__parallel_generation__"
        last_error: HTTPException | None = None
        for attempt in range(GENERATION_RETRY_LIMIT):
            repair_feedback = str(last_error.detail) if last_error is not None else None
            generated = OnboardingCalibrationService._generate_model_field_update(
                request_db,
                request_user_id,
                scope=scope,
                field_name=field_name,
                answers=answers,
                previous_name=previous_name,
                rejected_names=rejected_names,
                repair_feedback=repair_feedback,
                generation_context=generation_context,
                current_identity=current_identity,
                current_soul=current_soul,
            )
            try:
                OnboardingCalibrationService._assert_generated_field_shape(
                    generated,
                    scope=scope,
                    field_name=field_name,
                )
                cleaned = SettingsService.clean_agent_updates(dict(generated))
                cleaned_scope = cleaned.get(scope) or {}
                value = cleaned_scope.get(field_name)
                if not isinstance(value, str) or not value.strip():
                    raise HTTPException(
                        status_code=400,
                        detail=f"{scope}.{field_name} must be a non-empty string",
                    )
                if (
                    scope == "assistant_identity"
                    and field_name == "name"
                    and is_rejected_name(
                        value,
                        rejected_names=rejected_names,
                        previous_name=previous_name,
                    )
                ):
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            "assistant_identity.name must differ from every rejected "
                            "name in this calibration session"
                        ),
                    )
                return {scope: {field_name: value}}
            except HTTPException as exc:
                if exc.status_code != 400 or attempt == GENERATION_RETRY_LIMIT - 1:
                    if exc.status_code == 400:
                        raise HTTPException(
                            status_code=503,
                            detail=OnboardingCalibrationService._generation_failure_detail(
                                scope=scope,
                                field_name=field_name,
                            ),
                        ) from exc
                    raise
                last_error = exc

        raise HTTPException(
            status_code=503,
            detail=OnboardingCalibrationService._generation_failure_detail(
                scope=scope,
                field_name=field_name,
            ),
        )

    @staticmethod
    def _generate_model_field_update(
        db: Session,
        user_id: str,
        *,
        scope: str,
        field_name: str,
        answers: dict[str, Any],
        previous_name: str | None,
        rejected_names: list[str] | None,
        repair_feedback: str | None,
        generation_context: GenerationContext | None = None,
        current_identity: dict[str, Any] | None = None,
        current_soul: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Call the model for one field and parse the JSON response."""
        context = generation_context
        if context is None:
            if db is None or user_id is None:
                raise HTTPException(
                    status_code=409,
                    detail="Calibration cannot continue without user settings",
                )
            context = OnboardingCalibrationService._build_generation_context(
                db,
                user_id,
            )

        identity_payload = current_identity or context.current_identity
        soul_payload = current_soul or context.current_soul

        prompt = OnboardingCalibrationService._render_field_prompt(
            scope=scope,
            field_name=field_name,
            answers=answers,
            current_identity=identity_payload,
            current_soul=soul_payload,
            previous_name=previous_name,
            rejected_names=rejected_names,
            repair_feedback=repair_feedback,
        )

        gateway = AIProviderGateway(settings)

        def provider_key_lookup(provider: AIProvider) -> str | None:
            return context.provider_keys.get(provider)

        try:
            result = asyncio.run(
                gateway.generate_text(
                    prompt=prompt,
                    system_prompt=(
                        "You are sideBar authoring one assistant settings field. "
                        "Output valid JSON only."
                    ),
                    settings_record=context.settings_snapshot,
                    provider_key_lookup=provider_key_lookup,
                    max_output_tokens=OnboardingCalibrationService._field_token_budget(
                        scope=scope,
                        field_name=field_name,
                    ),
                    temperature=OnboardingCalibrationService._field_temperature(
                        scope=scope,
                        field_name=field_name,
                    ),
                )
            )
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(
                status_code=503,
                detail=OnboardingCalibrationService._generation_failure_detail(
                    scope=scope,
                    field_name=field_name,
                ),
            ) from exc
        return OnboardingCalibrationService._parse_generated_json_object(
            result.raw_text,
            scope=scope,
            field_name=field_name,
        )

    @staticmethod
    def _render_field_prompt(
        *,
        scope: str,
        field_name: str,
        answers: dict[str, Any],
        current_identity: dict[str, Any],
        current_soul: dict[str, Any],
        previous_name: str | None,
        rejected_names: list[str] | None,
        repair_feedback: str | None,
    ) -> str:
        """Render a field-specific calibration prompt."""
        template = FIELD_PROMPT_TEMPLATES[(scope, field_name)]
        return render_calibration_field_prompt(
            template=template,
            scope=scope,
            field_name=field_name,
            answers=answers,
            current_identity=current_identity,
            current_soul=current_soul,
            previous_name=previous_name,
            rejected_names=rejected_names,
            repair_feedback=repair_feedback,
        )

    @staticmethod
    def _parse_generated_json_object(
        raw_text: str,
        *,
        scope: str,
        field_name: str,
    ) -> dict[str, Any]:
        """Parse a model response into a JSON object."""
        candidate = raw_text.strip()
        if candidate.startswith("```"):
            lines = candidate.splitlines()
            if lines and lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].startswith("```"):
                lines = lines[:-1]
            candidate = "\n".join(lines).strip()
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            start = candidate.find("{")
            end = candidate.rfind("}")
            if start == -1 or end == -1 or end <= start:
                normalized = OnboardingCalibrationService._normalize_generated_payload(
                    candidate,
                    scope=scope,
                    field_name=field_name,
                )
                if normalized is not None:
                    return normalized
                raise HTTPException(
                    status_code=400,
                    detail=f"Generated invalid JSON for {scope}.{field_name}",
                ) from None
            try:
                parsed = json.loads(candidate[start : end + 1])
            except json.JSONDecodeError as exc:
                raise HTTPException(
                    status_code=400,
                    detail=f"Generated invalid JSON for {scope}.{field_name}",
                ) from exc
        normalized = OnboardingCalibrationService._normalize_generated_payload(
            parsed,
            scope=scope,
            field_name=field_name,
        )
        if normalized is not None:
            return normalized
        if not isinstance(parsed, dict):
            raise HTTPException(
                status_code=400,
                detail=f"Generated invalid JSON object for {scope}.{field_name}",
            )
        return parsed

    @staticmethod
    def _normalize_generated_payload(
        parsed: Any,
        *,
        scope: str,
        field_name: str,
    ) -> dict[str, Any] | None:
        """Normalize common near-miss model outputs into the expected field payload."""
        if isinstance(parsed, str):
            value = parsed.strip()
            if not value:
                return None
            return {scope: {field_name: value}}

        if not isinstance(parsed, dict):
            return None

        direct_value = parsed.get(field_name)
        if isinstance(direct_value, str):
            value = direct_value.strip()
            if value:
                return {scope: {field_name: value}}

        scoped_value = parsed.get(scope)
        if isinstance(scoped_value, str):
            value = scoped_value.strip()
            if value:
                return {scope: {field_name: value}}

        if isinstance(scoped_value, dict):
            nested_value = scoped_value.get(field_name)
            if isinstance(nested_value, str):
                value = nested_value.strip()
                if value:
                    return {scope: {field_name: value}}
        return None

    @staticmethod
    def _assert_generated_field_shape(
        generated: dict[str, Any],
        *,
        scope: str,
        field_name: str,
    ) -> None:
        """Ensure the model returned only the requested field."""
        if set(generated.keys()) != {scope}:
            raise HTTPException(
                status_code=400,
                detail=f"{scope}.{field_name} returned unexpected top-level keys",
            )
        scoped = generated.get(scope)
        if not isinstance(scoped, dict):
            raise HTTPException(
                status_code=400,
                detail=f"{scope}.{field_name} must return an object payload",
            )
        if set(scoped.keys()) != {field_name}:
            raise HTTPException(
                status_code=400,
                detail=f"{scope}.{field_name} returned unexpected nested keys",
            )

    @staticmethod
    def _raw_agent_payload(raw_value: Any) -> dict[str, Any]:
        """Return the stored assistant payload without metadata."""
        if not isinstance(raw_value, dict):
            return {}
        return {
            key: value
            for key, value in raw_value.items()
            if key != "_meta" and isinstance(value, str) and value.strip()
        }

    @staticmethod
    def _merge_generated_updates(
        target: dict[str, Any],
        incoming: dict[str, Any],
    ) -> None:
        """Merge a single generated field payload into a combined update payload."""
        for scope, scope_payload in incoming.items():
            existing_scope = target.setdefault(scope, {})
            if not isinstance(existing_scope, dict):
                existing_scope = {}
                target[scope] = existing_scope
            if isinstance(scope_payload, dict):
                existing_scope.update(scope_payload)

    @staticmethod
    def _generation_failure_detail(*, scope: str, field_name: str) -> str:
        """Return a user-facing retry message for calibration generation failures."""
        if (scope, field_name) == ("assistant_identity", "name"):
            return (
                "I couldn't choose a name just yet. "
                "Your setup is saved, please try again."
            )
        return (
            "I couldn't finish updating my setup just yet. "
            "Your answer is saved, please try again."
        )

    @staticmethod
    def _field_token_budget(*, scope: str, field_name: str) -> int:
        """Return the max output token budget for a calibration field."""
        return FIELD_MAX_OUTPUT_TOKENS.get((scope, field_name), 320)

    @staticmethod
    def _field_temperature(*, scope: str, field_name: str) -> float:
        """Return the sampling temperature for a calibration field."""
        return FIELD_TEMPERATURES.get((scope, field_name), 0.65)

    @staticmethod
    def _build_generation_context(db: Session, user_id: str) -> GenerationContext:
        """Capture the immutable inputs required for concurrent field generation."""
        settings_record = UserSettingsService.get_settings(db, user_id)
        if settings_record is None:
            raise HTTPException(
                status_code=409,
                detail="Calibration cannot continue without user settings",
            )

        primary_provider = AIPolicyService.resolve_from_settings(
            settings_record
        ).primary_provider
        provider_keys: dict[AIProvider, str | None] = {}
        if primary_provider is not None:
            provider_keys[primary_provider] = UserAIProviderKeyService.get_active_key(
                db,
                user_id,
                primary_provider,
            )
        settings_snapshot = SimpleNamespace(
            ai_primary_provider=getattr(settings_record, "ai_primary_provider", None)
        )
        return GenerationContext(
            settings_snapshot=settings_snapshot,
            current_identity=OnboardingCalibrationService._raw_agent_payload(
                getattr(settings_record, "assistant_identity", None)
            ),
            current_soul=OnboardingCalibrationService._raw_agent_payload(
                getattr(settings_record, "assistant_soul", None)
            ),
            provider_keys=provider_keys,
        )

    @staticmethod
    def _require_provider_ready(state: dict[str, Any]) -> None:
        """Reject calibration actions until the user has a connected provider."""
        if not bool(state.get("provider_ready")):
            raise HTTPException(
                status_code=409,
                detail=(
                    "Provider connection is required before calibration can continue"
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
