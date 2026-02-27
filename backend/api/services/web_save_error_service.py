"""Shared error classification helpers for web-save flows."""

from __future__ import annotations

import json
import re
from typing import Any

_DEFAULT_SUGGESTIONS: list[str] = [
    "Retry the save once to rule out transient network issues.",
    "If this persists, file a bug report with the provided bug_report_context.",
]

_SUGGESTIONS_BY_CODE: dict[str, list[str]] = {
    "WEB_SAVE_NO_READABLE_CONTENT": [
        "Confirm the URL points to readable article content and not an app shell.",
        "Try a public article URL instead of an authenticated dashboard page.",
    ],
    "WEB_SAVE_JINA_PAYMENT_REQUIRED": [
        "Check JINA_API_KEY billing/quota status.",
        "Verify the key has access to the Reader endpoint.",
    ],
    "WEB_SAVE_LOCAL_PARSE_AND_JINA_PAYMENT_REQUIRED": [
        "Check JINA_API_KEY billing/quota status.",
        "If this URL is app-like/auth-gated, local parsing may legitimately fail.",
    ],
    "WEB_SAVE_JINA_FETCH_FAILED": [
        "Verify the URL is reachable from the backend environment.",
        "Check Jina Reader API status and key permissions.",
    ],
    "WEB_SAVE_LOCAL_PARSE_AND_JINA_FETCH_FAILED": [
        "Verify the URL is reachable and not auth-gated.",
        "Check Jina Reader API status and key permissions.",
    ],
    "WEB_SAVE_JINA_API_KEY_MISSING": [
        "Configure JINA_API_KEY in runtime secrets.",
        "Retry after redeploying with updated environment variables.",
    ],
    "WEB_SAVE_VALIDATION_ERROR": [
        "Verify required parameters and URL formatting.",
    ],
}


def _compact_dict(payload: dict[str, Any]) -> dict[str, Any]:
    """Drop None/empty-string values from a dictionary."""
    compact: dict[str, Any] = {}
    for key, value in payload.items():
        if value is None:
            continue
        if isinstance(value, str) and value == "":
            continue
        compact[key] = value
    return compact


def _extract_http_status_code(message: str) -> int | None:
    """Extract an HTTP status code from an error message."""
    match = re.search(r"\b([1-5][0-9]{2})\s+Client Error\b", message)
    if match:
        return int(match.group(1))
    match = re.search(r"\bstatus(?:_code)?[=: ]+([1-5][0-9]{2})\b", message)
    if match:
        return int(match.group(1))
    return None


def _build_suggestions(code: str) -> list[str]:
    suggestions = list(_SUGGESTIONS_BY_CODE.get(code, _DEFAULT_SUGGESTIONS))
    for suggestion in _DEFAULT_SUGGESTIONS:
        if suggestion not in suggestions:
            suggestions.append(suggestion)
    return suggestions


def classify_web_save_failure(
    *,
    upstream_error_type: str | None,
    upstream_message: str | None,
    url: str | None = None,
    target_url: str | None = None,
    mode: str | None = None,
    local_parse_error: str | None = None,
) -> dict[str, Any]:
    """Classify a web-save failure into a stable error contract."""
    raw_type = (upstream_error_type or "").strip()
    raw_message = (upstream_message or "").strip()
    normalized_message = raw_message.lower()
    http_status_code = _extract_http_status_code(raw_message)

    local_parse_failed = bool(local_parse_error) or (
        "no readable content extracted" in normalized_message
        or "local parse failed" in normalized_message
    )
    jina_related = (
        "jina" in normalized_message
        or "r.jina.ai" in normalized_message
        or raw_type.lower() == "fetcherror"
    )
    payment_required = jina_related and (
        http_status_code == 402
        or ("402" in normalized_message and "payment required" in normalized_message)
    )
    missing_api_key = "jina_api_key" in normalized_message and (
        "not configured" in normalized_message or "not set" in normalized_message
    )

    if local_parse_failed and payment_required:
        code = "WEB_SAVE_LOCAL_PARSE_AND_JINA_PAYMENT_REQUIRED"
        message = (
            "Unable to save website: local parser found no readable content and "
            "Jina fallback returned 402 Payment Required."
        )
    elif payment_required:
        code = "WEB_SAVE_JINA_PAYMENT_REQUIRED"
        message = "Unable to save website: Jina fallback returned 402 Payment Required."
    elif missing_api_key:
        code = "WEB_SAVE_JINA_API_KEY_MISSING"
        message = "Unable to save website: JINA_API_KEY is not configured."
    elif local_parse_failed and jina_related:
        code = "WEB_SAVE_LOCAL_PARSE_AND_JINA_FETCH_FAILED"
        message = (
            "Unable to save website: local parser found no readable content and "
            "Jina fallback failed."
        )
    elif local_parse_failed:
        code = "WEB_SAVE_NO_READABLE_CONTENT"
        message = "Unable to save website: local parser found no readable content."
    elif jina_related:
        code = "WEB_SAVE_JINA_FETCH_FAILED"
        message = "Unable to save website: Jina fallback failed."
    elif raw_type == "ValidationError":
        code = "WEB_SAVE_VALIDATION_ERROR"
        message = raw_message or "Unable to save website: validation error."
    else:
        code = "WEB_SAVE_UNEXPECTED_ERROR"
        message = raw_message or "Unable to save website."

    details = _compact_dict(
        {
            "reason": code.lower(),
            "upstream_error_type": raw_type,
            "upstream_error": raw_message,
            "http_status_code": http_status_code,
            "url": url,
            "target_url": target_url,
            "mode": mode,
            "local_parse_error": local_parse_error,
        }
    )
    details["bug_report_context"] = _compact_dict(
        {
            "error_code": code,
            "upstream_error_type": raw_type,
            "http_status_code": http_status_code,
            "url": url,
            "target_url": target_url,
            "mode": mode,
            "local_parse_error": local_parse_error,
        }
    )

    return {
        "code": code,
        "message": message,
        "details": details,
        "suggestions": _build_suggestions(code),
    }


def classify_web_save_result(
    result: dict[str, Any],
    *,
    url: str | None = None,
    target_url: str | None = None,
    mode: str | None = None,
) -> dict[str, Any]:
    """Normalize a failed skill result into a structured web-save error."""
    error = result.get("error")
    if isinstance(error, dict):
        code = error.get("code")
        message = error.get("message")
        details = error.get("details")
        suggestions = error.get("suggestions")
        if isinstance(code, str) and isinstance(message, str):
            merged_details: dict[str, Any] = {}
            if isinstance(details, dict):
                merged_details.update(details)
            merged_details = _compact_dict(
                {
                    **merged_details,
                    "url": merged_details.get("url") or url,
                    "target_url": merged_details.get("target_url") or target_url,
                    "mode": merged_details.get("mode") or mode,
                }
            )
            merged_details["bug_report_context"] = _compact_dict(
                {
                    **(merged_details.get("bug_report_context") or {}),
                    "error_code": code,
                    "url": merged_details.get("url"),
                    "target_url": merged_details.get("target_url"),
                    "mode": merged_details.get("mode"),
                    "http_status_code": merged_details.get("http_status_code"),
                }
            )
            return {
                "code": code,
                "message": message,
                "details": merged_details,
                "suggestions": (
                    list(suggestions)
                    if isinstance(suggestions, list)
                    else _build_suggestions(code)
                ),
            }
        upstream_type = str(error.get("type") or "")
        upstream_message = str(error.get("message") or "")
        local_parse_error = None
        details_payload = error.get("details")
        if isinstance(details_payload, dict):
            local_parse = details_payload.get("local_parse_error")
            if isinstance(local_parse, str):
                local_parse_error = local_parse
        return classify_web_save_failure(
            upstream_error_type=upstream_type,
            upstream_message=upstream_message,
            local_parse_error=local_parse_error,
            url=url,
            target_url=target_url,
            mode=mode,
        )

    return classify_web_save_failure(
        upstream_error_type="",
        upstream_message=str(error or ""),
        url=url,
        target_url=target_url,
        mode=mode,
    )


def encode_job_error(error_payload: dict[str, Any]) -> str:
    """Serialize a structured quick-save error payload for persistence."""
    return json.dumps(error_payload, sort_keys=True)


def decode_job_error(
    raw_error_message: str | None,
) -> tuple[str | None, dict[str, Any] | None]:
    """Decode persisted quick-save error payload into message + details."""
    if not raw_error_message:
        return None, None
    try:
        parsed = json.loads(raw_error_message)
    except (json.JSONDecodeError, TypeError):
        return raw_error_message, None
    if not isinstance(parsed, dict):
        return raw_error_message, None
    message = parsed.get("message")
    if isinstance(message, str) and message.strip():
        return message, parsed
    return raw_error_message, None
