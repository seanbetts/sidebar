"""Service helpers for creating GitHub issues from product feedback."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any, Literal
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from api.config import settings
from api.prompt_formatters import detect_operating_system

FeedbackIssueType = Literal["bug", "feature"]


class GitHubIssueService:
    """Create GitHub issues using repository-scoped API credentials."""

    _DEFAULT_USER_AGENT = "sideBar-product-feedback"
    _API_VERSION = "2022-11-28"
    _ISSUE_LABELS: dict[FeedbackIssueType, str] = {
        "bug": "bug",
        "feature": "feature-request",
    }
    _TITLE_PREFIXES: dict[FeedbackIssueType, str] = {
        "bug": "[Bug]",
        "feature": "[Feature]",
    }

    @classmethod
    def submit_feedback_issue(
        cls,
        *,
        issue_type: FeedbackIssueType,
        summary: str | None,
        details: str | None = None,
        user_id: str,
        user_agent: str | None = None,
        conversation_id: str | None = None,
        user_message_id: str | None = None,
        assistant_message_id: str | None = None,
    ) -> dict[str, Any]:
        """Submit a bug report or feature request issue to GitHub."""
        owner, repo, token = cls._resolve_config()
        normalized_summary = cls._normalize_summary(summary, details, issue_type)
        platform = detect_operating_system(user_agent) or "Unknown"
        issue_body = cls._build_issue_body(
            issue_type=issue_type,
            summary=normalized_summary,
            details=details,
            user_id=user_id,
            platform=platform,
            conversation_id=conversation_id,
            user_message_id=user_message_id,
            assistant_message_id=assistant_message_id,
            user_agent=user_agent,
        )
        label = cls._ISSUE_LABELS[issue_type]
        issue_payload = {
            "title": f"{cls._TITLE_PREFIXES[issue_type]} {normalized_summary}",
            "body": issue_body,
            "labels": [label],
        }
        api_base = settings.github_issues_api_base.rstrip("/")
        url = f"{api_base}/repos/{owner}/{repo}/issues"

        try:
            response_payload = cls._post_issue(url, token, issue_payload)
            labels_applied = [label]
        except ValueError as exc:
            # If labels are missing in the repo, retry without labels to avoid
            # blocking user feedback submission.
            if not cls._is_label_validation_error(str(exc)):
                raise
            issue_payload.pop("labels", None)
            response_payload = cls._post_issue(url, token, issue_payload)
            labels_applied = []

        return {
            "issue_number": response_payload.get("number"),
            "issue_url": response_payload.get("html_url"),
            "issue_title": response_payload.get("title"),
            "issue_type": issue_type,
            "platform": platform,
            "labels_applied": labels_applied,
            "repository": f"{owner}/{repo}",
        }

    @staticmethod
    def _resolve_config() -> tuple[str, str, str]:
        owner = (settings.github_issues_owner or "").strip()
        repo = (settings.github_issues_repo or "").strip()
        token = (settings.github_issues_token or "").strip()
        if not owner or not repo or not token:
            raise ValueError(
                "GitHub issue submission is not configured. "
                "Set GITHUB_ISSUES_OWNER, GITHUB_ISSUES_REPO, and GITHUB_ISSUES_TOKEN."
            )
        return owner, repo, token

    @classmethod
    def _normalize_summary(
        cls,
        summary: str | None,
        details: str | None,
        issue_type: FeedbackIssueType,
    ) -> str:
        summary_value = (summary or "").strip()
        if summary_value:
            return " ".join(summary_value.split())[:140]

        details_value = (details or "").strip()
        if details_value:
            first_line = details_value.splitlines()[0].strip()
            if first_line:
                return " ".join(first_line.split())[:140]

        fallback_prefix = (
            "User-submitted bug report"
            if issue_type == "bug"
            else ("User-submitted feature request")
        )
        return f"{fallback_prefix} ({datetime.now(UTC).strftime('%Y-%m-%d %H:%M UTC')})"

    @classmethod
    def _build_issue_body(
        cls,
        *,
        issue_type: FeedbackIssueType,
        summary: str,
        details: str | None,
        user_id: str,
        platform: str,
        conversation_id: str | None,
        user_message_id: str | None,
        assistant_message_id: str | None,
        user_agent: str | None,
    ) -> str:
        now_iso = datetime.now(UTC).isoformat()
        kind_text = "Bug Report" if issue_type == "bug" else "Feature Request"
        lines = [f"## {kind_text}", "", summary.strip()]

        cleaned_details = (details or "").strip()
        if cleaned_details:
            lines.extend(["", "## Details", "", cleaned_details])

        lines.extend(
            [
                "",
                "## Metadata",
                "",
                f"- `submitted_at`: {now_iso}",
                f"- `user_id`: {user_id}",
                f"- `platform`: {platform}",
                f"- `conversation_id`: {(conversation_id or '').strip() or 'unknown'}",
                f"- `user_message_id`: {(user_message_id or '').strip() or 'unknown'}",
                "- `assistant_message_id`: "
                f"{(assistant_message_id or '').strip() or 'unknown'}",
            ]
        )
        if user_agent and user_agent.strip():
            lines.append(f"- `user_agent`: {user_agent.strip()[:300]}")

        return "\n".join(lines)

    @classmethod
    def _post_issue(
        cls, url: str, token: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": cls._API_VERSION,
            "User-Agent": cls._DEFAULT_USER_AGENT,
            "Content-Type": "application/json",
        }
        request = Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )

        try:
            with urlopen(request, timeout=15) as response:
                raw_body = response.read().decode("utf-8")
                parsed = json.loads(raw_body or "{}")
                if not isinstance(parsed, dict):
                    raise ValueError("Unexpected GitHub response payload")
                return parsed
        except HTTPError as exc:
            raw_error = exc.read().decode("utf-8", errors="replace")
            parsed_error = cls._safe_parse_json(raw_error)
            message = cls._extract_error_message(parsed_error, raw_error)
            raise ValueError(
                f"GitHub issue creation failed ({exc.code}): {message}"
            ) from exc
        except URLError as exc:
            raise ValueError(f"GitHub issue creation failed: {exc.reason}") from exc

    @staticmethod
    def _safe_parse_json(value: str) -> dict[str, Any]:
        try:
            parsed = json.loads(value or "{}")
        except json.JSONDecodeError:
            return {}
        if isinstance(parsed, dict):
            return parsed
        return {}

    @staticmethod
    def _extract_error_message(parsed_error: dict[str, Any], raw_error: str) -> str:
        message = parsed_error.get("message")
        if isinstance(message, str) and message.strip():
            errors = parsed_error.get("errors")
            if isinstance(errors, list) and errors:
                return f"{message}: {json.dumps(errors)}"
            return message.strip()
        trimmed = raw_error.strip()
        return trimmed[:300] if trimmed else "Unknown GitHub API error"

    @staticmethod
    def _is_label_validation_error(error_message: str) -> bool:
        lower_message = error_message.lower()
        return "label" in lower_message and "validation failed" in lower_message
