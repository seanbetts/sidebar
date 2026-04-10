"""Backend-owned notification policy decisions for Task 7."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from api.services.notification_types import (
    NotificationCategory,
    NotificationIntent,
    NotificationPolicyDecision,
)
from api.services.settings_notifications import resolve_notification_preferences


@dataclass(frozen=True, slots=True)
class _CategoryPolicy:
    enabled_field: str
    schedule_time_field: str | None = None
    requires_away: bool = False


class NotificationPolicyService:
    """Apply preference defaults, schedule rules, and away-state gating."""

    CATEGORY_POLICIES = {
        NotificationCategory.TASK_REMINDER: _CategoryPolicy(
            enabled_field="task_reminders_enabled",
            schedule_time_field="task_reminder_time",
        ),
        NotificationCategory.MORNING_DIGEST: _CategoryPolicy(
            enabled_field="morning_digest_enabled",
            schedule_time_field="morning_digest_time",
        ),
        NotificationCategory.ASSISTANT_REPLY: _CategoryPolicy(
            enabled_field="assistant_reply_notifications_enabled",
            requires_away=True,
        ),
        NotificationCategory.ASSISTANT_PROACTIVE: _CategoryPolicy(
            enabled_field="assistant_proactive_notifications_enabled",
        ),
    }

    @classmethod
    def evaluate(
        cls,
        intent: NotificationIntent,
        *,
        settings_record: Any = None,
        device_tokens: list[Any] | tuple[Any, ...] | None = None,
    ) -> NotificationPolicyDecision:
        """Return the policy decision for one notification intent."""
        preferences = resolve_notification_preferences(settings_record)
        policy = cls.CATEGORY_POLICIES[intent.category]
        if preferences.get(policy.enabled_field) is not True:
            return NotificationPolicyDecision(False, reason="disabled")

        if policy.schedule_time_field and (
            not preferences.get(policy.schedule_time_field)
            or not preferences.get("schedule_timezone")
        ):
            return NotificationPolicyDecision(False, reason="schedule_incomplete")

        matched_tokens = cls._match_capability_tokens(
            device_tokens or (),
            intent.required_capabilities,
        )
        if intent.required_capabilities and not matched_tokens:
            return NotificationPolicyDecision(
                False,
                reason="missing_required_capability",
            )

        if (policy.requires_away or intent.requires_away) and cls._is_user_present(
            device_tokens or ()
        ):
            return NotificationPolicyDecision(False, reason="user_present")

        return NotificationPolicyDecision(
            True,
            matched_tokens=matched_tokens or tuple(device_tokens or ()),
        )

    @staticmethod
    def _match_capability_tokens(
        device_tokens: list[Any] | tuple[Any, ...],
        required_capabilities: tuple[str, ...],
    ) -> tuple[Any, ...]:
        """Return tokens that satisfy all required capability flags."""
        if not required_capabilities:
            return tuple(device_tokens)

        matched = []
        for token in device_tokens:
            capabilities = getattr(token, "capabilities", {}) or {}
            if all(
                capabilities.get(capability) is True
                for capability in required_capabilities
            ):
                matched.append(token)
        return tuple(matched)

    @staticmethod
    def _is_user_present(device_tokens: list[Any] | tuple[Any, ...]) -> bool:
        """Treat any foreground token as proof that the user is present."""
        return any(
            bool(getattr(token, "is_foreground", False)) for token in device_tokens
        )
