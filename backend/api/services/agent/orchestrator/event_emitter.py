"""Helpers for mapping internal state into streamable agent events."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

from api.services.ai.chat_stream_custom_events import build_custom_chat_stream_event


def _base_onboarding_payload(
    onboarding_state: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if not isinstance(onboarding_state, dict):
        return None
    return {
        "current_onboarding_step": str(
            onboarding_state.get("current_onboarding_step", "")
        ),
        "provider_ready": bool(onboarding_state.get("provider_ready")),
    }


def build_onboarding_provider_blocked_event(
    onboarding_state: dict[str, Any] | None,
) -> dict[str, Any] | None:
    """Return a provider-blocked stream event when onboarding is blocked on setup."""
    payload = _base_onboarding_payload(onboarding_state)
    if payload is None:
        return None
    if payload["current_onboarding_step"] != "provider_recovery":
        return None
    return build_custom_chat_stream_event("onboarding_provider_blocked", payload)


def build_onboarding_resume_suggested_event(
    onboarding_state: dict[str, Any] | None,
) -> dict[str, Any] | None:
    """Return a resume-suggested event for recoverable onboarding states."""
    payload = _base_onboarding_payload(onboarding_state)
    if payload is None:
        return None
    if payload["current_onboarding_step"] not in {
        "permission_recovery",
        "feature_discovery",
    }:
        return None
    return build_custom_chat_stream_event("onboarding_resume_suggested", payload)


def build_onboarding_milestone_completed_event(
    onboarding_state: dict[str, Any] | None,
    milestone: str | None,
) -> dict[str, Any] | None:
    """Return a milestone-completed event when a concrete milestone is provided."""
    payload = _base_onboarding_payload(onboarding_state)
    if payload is None or not isinstance(milestone, str) or not milestone.strip():
        return None
    payload["milestone"] = milestone.strip()
    return build_custom_chat_stream_event("onboarding_milestone_completed", payload)


def iter_initial_onboarding_events(
    onboarding_state: dict[str, Any] | None,
) -> Iterator[dict[str, Any]]:
    """Yield the onboarding recovery preamble events for the current state."""
    provider_blocked = build_onboarding_provider_blocked_event(onboarding_state)
    if provider_blocked is not None:
        yield provider_blocked
        return

    resume_suggested = build_onboarding_resume_suggested_event(onboarding_state)
    if resume_suggested is not None:
        yield resume_suggested


__all__ = [
    "build_onboarding_milestone_completed_event",
    "build_onboarding_provider_blocked_event",
    "build_onboarding_resume_suggested_event",
    "iter_initial_onboarding_events",
]
