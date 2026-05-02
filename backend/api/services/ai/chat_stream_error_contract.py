"""Structured chat stream error payloads for provider and stream failures."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Literal, cast

from api.services.ai.registry import AIProvider

ChatStreamErrorCategory = Literal[
    "provider_billing",
    "provider_rate_limited",
    "auth_or_permission",
    "provider_overloaded",
    "request_timeout",
    "context_too_large",
    "transport_failure",
    "empty_response",
    "tool_exhaustion",
    "provider_error",
    "user_cancelled",
    "unknown",
]

_VALID_CATEGORIES: set[str] = {
    "provider_billing",
    "provider_rate_limited",
    "auth_or_permission",
    "provider_overloaded",
    "request_timeout",
    "context_too_large",
    "transport_failure",
    "empty_response",
    "tool_exhaustion",
    "provider_error",
    "user_cancelled",
    "unknown",
}

_RETRYABLE_CATEGORIES = {
    "provider_rate_limited",
    "provider_overloaded",
    "request_timeout",
    "transport_failure",
    "empty_response",
    "provider_error",
}

_USER_ACTION_REQUIRED_CATEGORIES = {
    "provider_billing",
    "auth_or_permission",
    "context_too_large",
}

_SAFE_MESSAGES: dict[str, str] = {
    "provider_billing": "The AI provider account needs billing attention.",
    "provider_rate_limited": (
        "The AI provider is rate limited right now. Please wait a moment and try again."
    ),
    "auth_or_permission": "Authentication failed for the AI provider.",
    "provider_overloaded": (
        "The AI provider is busy right now. Please try again in a moment."
    ),
    "request_timeout": "The AI provider took too long to respond. Please try again.",
    "context_too_large": (
        "This request is too large to retry without reducing context."
    ),
    "transport_failure": "The network connection was interrupted. Please try again.",
    "empty_response": "The AI provider returned an empty response. Please try again.",
    "tool_exhaustion": (
        "I couldn't finish this response because it needed too many tool steps. "
        "Try a narrower follow-up."
    ),
    "provider_error": "The AI provider hit an error. Please try again.",
    "user_cancelled": "The request was cancelled before it completed.",
    "unknown": "The response hit an error. Please try again.",
}


def build_chat_stream_error_event(
    error: Exception | str,
    *,
    provider: AIProvider | str | None = None,
    category: ChatStreamErrorCategory | str | None = None,
) -> dict[str, Any]:
    """Return a structured SSE error payload with legacy fallback text."""
    raw_message = str(error)
    extracted = _extract_error_fields(error)
    normalized_category = _normalize_category(
        explicit_category=category,
        provider_error_type=extracted["provider_error_type"],
        provider_error_code=extracted["provider_error_code"],
        http_status=extracted["http_status"],
        message=extracted["message"] or raw_message,
        error_class=type(error).__name__ if not isinstance(error, str) else None,
    )
    safe_message = _SAFE_MESSAGES[normalized_category]
    details: dict[str, Any] = {
        "category": normalized_category,
        "message": extracted["message"] or raw_message,
        "retryable": normalized_category in _RETRYABLE_CATEGORIES,
        "user_action_required": normalized_category in _USER_ACTION_REQUIRED_CATEGORIES,
    }
    provider_name = _clean_string(provider)
    if provider_name:
        details["provider"] = provider_name
    for source_key, target_key in (
        ("provider_error_type", "provider_error_type"),
        ("provider_error_code", "provider_error_code"),
        ("http_status", "http_status"),
        ("request_id", "request_id"),
        ("retry_after_seconds", "retry_after_seconds"),
    ):
        value = extracted[source_key]
        if value is not None:
            details[target_key] = value

    return {
        "type": "error",
        "version": 1,
        "error": safe_message,
        "error_details": details,
    }


def _extract_error_fields(error: Exception | str) -> dict[str, Any]:
    body = _mapping_or_none(getattr(error, "body", None))
    nested_error = _mapping_or_none(body.get("error")) if body else None
    details = _mapping_or_none(getattr(error, "details", None))
    details_error = _mapping_or_none(details.get("error")) if details else None

    provider_error_type = _first_string(
        getattr(error, "type", None),
        nested_error.get("type") if nested_error else None,
        body.get("type") if body else None,
        getattr(error, "status", None),
        details_error.get("status") if details_error else None,
        details.get("status") if details else None,
    )
    provider_error_code = _first_string(
        getattr(error, "code", None),
        nested_error.get("code") if nested_error else None,
        body.get("code") if body else None,
        details_error.get("code") if details_error else None,
        details.get("code") if details else None,
    )
    http_status = _first_int(
        getattr(error, "status_code", None),
        getattr(error, "code", None),
        details_error.get("code") if details_error else None,
        details.get("code") if details else None,
    )
    message = _first_string(
        getattr(error, "message", None),
        nested_error.get("message") if nested_error else None,
        body.get("message") if body else None,
        details_error.get("message") if details_error else None,
        details.get("message") if details else None,
    )
    request_id = _first_string(
        getattr(error, "request_id", None),
        body.get("request_id") if body else None,
        getattr(getattr(error, "response", None), "headers", {}).get("request-id")
        if getattr(error, "response", None) is not None
        else None,
    )
    retry_after_seconds = _retry_after_seconds(error)

    return {
        "provider_error_type": provider_error_type,
        "provider_error_code": provider_error_code,
        "http_status": http_status,
        "message": message,
        "request_id": request_id,
        "retry_after_seconds": retry_after_seconds,
    }


def _normalize_category(
    *,
    explicit_category: str | None,
    provider_error_type: str | None,
    provider_error_code: str | None,
    http_status: int | None,
    message: str,
    error_class: str | None,
) -> ChatStreamErrorCategory:
    if explicit_category in _VALID_CATEGORIES:
        return cast(ChatStreamErrorCategory, explicit_category)

    tokens = {
        _normalize_token(provider_error_type),
        _normalize_token(provider_error_code),
        _normalize_token(error_class),
    }
    message_text = message.lower()

    if _has_billing_signal(tokens, message_text, http_status):
        return "provider_billing"
    if http_status in {401, 403} or tokens & {
        "authentication_error",
        "permission_error",
        "permission_denied",
        "authenticationerror",
        "permissiondeniederror",
    }:
        return "auth_or_permission"
    if http_status == 413 or tokens & {
        "request_too_large",
        "context_length_exceeded",
    }:
        return "context_too_large"
    if "context length exceeded" in message_text or "prompt too large" in message_text:
        return "context_too_large"
    if (
        http_status == 429
        or tokens & {"rate_limit_error", "rate_limit_exceeded"}
        or "rate_limit" in message_text
        or "rate limit" in message_text
        or "rate limited" in message_text
    ):
        return "provider_rate_limited"
    if http_status in {529, 503} or tokens & {
        "overloaded_error",
        "unavailable",
        "overloadederror",
        "serviceunavailableerror",
    }:
        return "provider_overloaded"
    if http_status in {408, 504} or tokens & {
        "timeout_error",
        "deadline_exceeded",
        "apitimeouterror",
        "deadlineexceedederror",
    }:
        return "request_timeout"
    if tokens & {"apiconnectionerror"} or any(
        marker in message_text
        for marker in ("connection error", "connection reset", "network")
    ):
        return "transport_failure"
    if error_class == "CancellationError" or "cancelled" in message_text:
        return "user_cancelled"
    if http_status is not None and http_status >= 500:
        return "provider_error"
    return "unknown"


def _has_billing_signal(
    tokens: set[str],
    message_text: str,
    http_status: int | None,
) -> bool:
    if tokens & {"billing_error", "insufficient_quota", "failed_precondition"}:
        return True
    billing_markers = (
        "billing",
        "credit",
        "credits",
        "quota",
        "current quota",
        "monthly spend",
        "paid plan",
    )
    if any(marker in message_text for marker in billing_markers):
        return http_status in {400, 402, 429} or "exceeded" in message_text
    return False


def _retry_after_seconds(error: Exception | str) -> int | None:
    response = getattr(error, "response", None)
    headers = getattr(response, "headers", None)
    if not isinstance(headers, Mapping):
        return None
    value = headers.get("retry-after") or headers.get("Retry-After")
    if value is None:
        return None
    try:
        seconds = int(str(value).strip())
    except ValueError:
        return None
    return seconds if seconds >= 0 else None


def _mapping_or_none(value: Any) -> Mapping[str, Any] | None:
    return value if isinstance(value, Mapping) else None


def _first_string(*values: Any) -> str | None:
    for value in values:
        cleaned = _clean_string(value)
        if cleaned:
            return cleaned
    return None


def _first_int(*values: Any) -> int | None:
    for value in values:
        if isinstance(value, bool):
            continue
        if isinstance(value, int):
            return value
        if isinstance(value, str):
            try:
                return int(value)
            except ValueError:
                continue
    return None


def _clean_string(value: Any) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _normalize_token(value: Any) -> str:
    cleaned = _clean_string(value)
    return cleaned.lower() if cleaned else ""
