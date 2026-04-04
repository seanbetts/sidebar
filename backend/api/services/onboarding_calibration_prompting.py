"""Prompt helpers for onboarding calibration generation."""

from __future__ import annotations

import json
from typing import Any

from api.services.agent.prompt.sections import resolve_template
from api.services.agent.prompt.templates import (
    CALIBRATION_AUTHORING_PRINCIPLES,
    CALIBRATION_CORE_SIDEBAR_CHARACTER,
    CALIBRATION_OUTPUT_RULES,
)


def normalized_rejected_names(
    *,
    rejected_names: list[str] | None,
    previous_name: str | None,
) -> list[str]:
    """Return normalized, de-duplicated rejected names for this session."""
    combined = list(rejected_names or [])
    if previous_name is not None:
        combined.append(previous_name)

    normalized_names: list[str] = []
    seen: set[str] = set()
    for candidate in combined:
        if not isinstance(candidate, str):
            continue
        normalized = candidate.strip()
        if not normalized:
            continue
        dedupe_key = normalized.casefold()
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        normalized_names.append(normalized)
    return normalized_names


def is_rejected_name(
    candidate_name: str,
    *,
    rejected_names: list[str] | None,
    previous_name: str | None,
) -> bool:
    """Return True when the candidate repeats a rejected session name."""
    normalized_candidate = candidate_name.strip().casefold()
    if not normalized_candidate:
        return False
    return normalized_candidate in {
        name.casefold()
        for name in normalized_rejected_names(
            rejected_names=rejected_names,
            previous_name=previous_name,
        )
    }


def render_calibration_field_prompt(
    *,
    template: str,
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
    variables = {
        "calibration_authoring_principles": CALIBRATION_AUTHORING_PRINCIPLES,
        "calibration_core_sidebar_character": CALIBRATION_CORE_SIDEBAR_CHARACTER,
        "calibration_output_rules": CALIBRATION_OUTPUT_RULES,
        "primary_goal": str(answers.get("primary_goal") or "").strip() or "None",
        "working_relationship": (
            str(answers.get("working_relationship") or "").strip() or "None"
        ),
        "tone_preferences": (
            str(answers.get("tone_preferences") or "").strip() or "None"
        ),
        "assistant_soul_json": json.dumps(
            current_soul,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        ),
        "assistant_identity_json": json.dumps(
            current_identity,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        ),
        "previous_name": (previous_name or "None"),
        "rejected_names_json": json.dumps(
            normalized_rejected_names(
                rejected_names=rejected_names,
                previous_name=previous_name,
            ),
            ensure_ascii=True,
            separators=(",", ":"),
        ),
    }
    rendered = resolve_template(template, variables, keep_unknown=False).strip()
    if repair_feedback:
        expected_json = json.dumps(
            {scope: {field_name: "<write the field value here>"}},
            ensure_ascii=True,
            separators=(",", ":"),
        )
        rendered += (
            "\n\nRetry guidance:\n"
            "The previous attempt failed validation. Correct it.\n"
            f"Return exactly this JSON shape: {expected_json}\n"
            "No markdown, no explanation, and no extra keys.\n"
            f"Validation feedback: {repair_feedback}"
        )
    return rendered
