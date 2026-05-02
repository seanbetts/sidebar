from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from api.services.ai.chat_stream_error_contract import build_chat_stream_error_event


@dataclass
class FakeProviderError(Exception):
    raw_message: str
    status_code: int | None = None
    body: dict[str, Any] | None = None
    request_id: str | None = None
    code: int | None = None
    status: str | None = None
    sdk_message: str | None = None
    details: dict[str, Any] | None = None

    @property
    def message(self) -> str:
        return self.sdk_message or self.raw_message

    def __str__(self) -> str:
        return self.raw_message


def _details(payload: dict[str, Any]) -> dict[str, Any]:
    details = payload["error_details"]
    assert isinstance(details, dict)
    return details


def test_openai_insufficient_quota_maps_to_provider_billing() -> None:
    error = FakeProviderError(
        "quota exhausted",
        status_code=429,
        body={
            "type": "insufficient_quota",
            "code": "insufficient_quota",
            "message": (
                "You exceeded your current quota, please check your plan and "
                "billing details."
            ),
        },
        request_id="req_openai",
    )

    payload = build_chat_stream_error_event(error, provider="openai")
    details = _details(payload)

    assert payload["type"] == "error"
    assert payload["version"] == 1
    assert details["category"] == "provider_billing"
    assert details["provider"] == "openai"
    assert details["provider_error_type"] == "insufficient_quota"
    assert details["provider_error_code"] == "insufficient_quota"
    assert details["http_status"] == 429
    assert details["request_id"] == "req_openai"
    assert details["retryable"] is False
    assert details["user_action_required"] is True


def test_openai_rate_limit_without_quota_text_maps_to_rate_limited() -> None:
    error = FakeProviderError(
        "rate limit reached",
        status_code=429,
        body={
            "type": "rate_limit_error",
            "code": "rate_limit_exceeded",
            "message": "Rate limit reached for requests.",
        },
    )

    details = _details(build_chat_stream_error_event(error, provider="openai"))

    assert details["category"] == "provider_rate_limited"
    assert details["retryable"] is True
    assert details["user_action_required"] is False


def test_anthropic_billing_error_maps_to_provider_billing() -> None:
    error = FakeProviderError(
        "billing problem",
        status_code=402,
        body={
            "error": {
                "type": "billing_error",
                "message": "There is an issue with your billing information.",
            },
            "request_id": "req_anthropic",
        },
    )

    details = _details(build_chat_stream_error_event(error, provider="anthropic"))

    assert details["category"] == "provider_billing"
    assert details["provider_error_type"] == "billing_error"
    assert details["request_id"] == "req_anthropic"
    assert details["retryable"] is False


def test_google_failed_precondition_billing_setup_maps_to_provider_billing() -> None:
    error = FakeProviderError(
        "400 FAILED_PRECONDITION. paid plan required",
        code=400,
        status="FAILED_PRECONDITION",
        sdk_message="To use the Gemini API, setup a paid plan using Google AI Studio.",
        details={
            "error": {
                "code": 400,
                "status": "FAILED_PRECONDITION",
                "message": (
                    "To use the Gemini API, you will need to setup a paid plan."
                ),
            }
        },
    )

    details = _details(build_chat_stream_error_event(error, provider="google"))

    assert details["category"] == "provider_billing"
    assert details["http_status"] == 400
    assert details["provider_error_type"] == "FAILED_PRECONDITION"
    assert details["user_action_required"] is True


def test_google_resource_exhausted_quota_message_maps_to_provider_billing() -> None:
    error = FakeProviderError(
        "429 RESOURCE_EXHAUSTED. quota exhausted",
        code=429,
        status="RESOURCE_EXHAUSTED",
        sdk_message=(
            "You exceeded your current quota, please check your plan and billing details."
        ),
    )

    details = _details(build_chat_stream_error_event(error, provider="google"))

    assert details["category"] == "provider_billing"
    assert details["retryable"] is False


def test_google_resource_exhausted_rate_limit_maps_to_rate_limited() -> None:
    error = FakeProviderError(
        "429 RESOURCE_EXHAUSTED. rate limit",
        code=429,
        status="RESOURCE_EXHAUSTED",
        sdk_message="You've exceeded the rate limit.",
    )

    details = _details(build_chat_stream_error_event(error, provider="google"))

    assert details["category"] == "provider_rate_limited"
    assert details["retryable"] is True


def test_provider_auth_failure_maps_to_auth_or_permission() -> None:
    error = FakeProviderError(
        "invalid key",
        status_code=401,
        body={"type": "authentication_error", "message": "Invalid API key."},
    )

    details = _details(build_chat_stream_error_event(error, provider="anthropic"))

    assert details["category"] == "auth_or_permission"
    assert details["retryable"] is False
    assert details["user_action_required"] is True


def test_provider_overload_and_timeout_categories_are_retryable() -> None:
    overloaded = FakeProviderError(
        "overloaded",
        status_code=529,
        body={"error": {"type": "overloaded_error", "message": "Overloaded"}},
    )
    timeout = FakeProviderError("deadline", code=504, status="DEADLINE_EXCEEDED")

    overloaded_details = _details(
        build_chat_stream_error_event(overloaded, provider="anthropic")
    )
    timeout_details = _details(
        build_chat_stream_error_event(timeout, provider="google")
    )

    assert overloaded_details["category"] == "provider_overloaded"
    assert overloaded_details["retryable"] is True
    assert timeout_details["category"] == "request_timeout"
    assert timeout_details["retryable"] is True


def test_context_too_large_and_unknown_fallback_are_non_retryable() -> None:
    too_large = FakeProviderError(
        "too large",
        status_code=413,
        body={"error": {"type": "request_too_large", "message": "Request too large."}},
    )
    unknown = RuntimeError("provider emitted an unexpected fatal condition")

    too_large_details = _details(
        build_chat_stream_error_event(too_large, provider="anthropic")
    )
    unknown_details = _details(build_chat_stream_error_event(unknown))

    assert too_large_details["category"] == "context_too_large"
    assert too_large_details["retryable"] is False
    assert unknown_details["category"] == "unknown"
    assert unknown_details["retryable"] is False


def test_explicit_internal_categories_emit_structured_payload() -> None:
    empty_response = build_chat_stream_error_event(
        "Google response contained no text and no tool calls",
        provider="google",
        category="empty_response",
    )
    tool_exhaustion = build_chat_stream_error_event(
        "Maximum tool rounds reached before completion",
        category="tool_exhaustion",
    )

    assert _details(empty_response)["category"] == "empty_response"
    assert _details(empty_response)["retryable"] is True
    assert _details(tool_exhaustion)["category"] == "tool_exhaustion"
    assert _details(tool_exhaustion)["retryable"] is False
