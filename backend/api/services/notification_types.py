"""Shared notification types used by Task 7 services."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any


class NotificationCategory(StrEnum):
    """Supported user-visible notification categories."""

    TASK_REMINDER = "task_reminder"
    MORNING_DIGEST = "morning_digest"
    ASSISTANT_REPLY = "assistant_reply"
    ASSISTANT_PROACTIVE = "assistant_proactive"
    TEST_PUSH = "test_push"


class NotificationDeliveryMode(StrEnum):
    """Delivery modes that notification transports may support."""

    ALERT = "alert"
    BADGE = "badge"
    LIVE_ACTIVITY = "live_activity"


@dataclass(frozen=True, slots=True)
class NotificationIntent:
    """Transport-agnostic notification intent created by product services."""

    user_id: str
    category: NotificationCategory
    delivery_mode: NotificationDeliveryMode
    title: str | None = None
    body: str | None = None
    route: str | None = None
    native_category: str | None = None
    thread_id: str | None = None
    badge_count: int | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    required_capabilities: tuple[str, ...] = ()
    requires_away: bool = False


@dataclass(frozen=True, slots=True)
class NotificationPolicyDecision:
    """Result of policy evaluation for a notification intent."""

    should_deliver: bool
    reason: str | None = None
    matched_tokens: tuple[Any, ...] = ()


@dataclass(frozen=True, slots=True)
class APNSNotificationRequest:
    """Concrete APNs request built by the delivery layer."""

    token: str
    platform: str
    payload: dict[str, Any]
    push_type: str
    priority: str
    topic: str | None = None
    installation_id: str | None = None


@dataclass(frozen=True, slots=True)
class APNSNotificationOutcome:
    """Per-request APNs outcome used for diagnostics auditing."""

    token: str
    platform: str
    topic: str | None
    environment: str
    status_code: int | None
    reason: str | None
    accepted: bool
    installation_id: str | None = None


@dataclass(frozen=True, slots=True)
class PushNotificationSendResult:
    """Transport-level APNs send summary."""

    attempted_count: int
    sent_count: int
    invalid_tokens: tuple[str, ...] = ()
    outcomes: tuple[APNSNotificationOutcome, ...] = ()


@dataclass(frozen=True, slots=True)
class NotificationDeliveryResult:
    """Delivery-layer result for one notification intent."""

    status: str
    request_count: int
    sent_count: int
    reason: str | None = None
    outcomes: tuple[APNSNotificationOutcome, ...] = ()
