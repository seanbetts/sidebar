import io
import json
from urllib.error import HTTPError

import pytest
from api.config import settings
from api.services import github_issue_service
from api.services.github_issue_service import GitHubIssueService


class _FakeHTTPResponse:
    def __init__(self, payload: dict):
        self._raw = json.dumps(payload).encode("utf-8")

    def read(self) -> bytes:
        return self._raw

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


def test_submit_feedback_issue_creates_github_issue(monkeypatch: pytest.MonkeyPatch):
    captured: dict[str, object] = {}

    def fake_urlopen(request, timeout=15):
        captured["url"] = request.full_url
        captured["timeout"] = timeout
        captured["headers"] = dict(request.header_items())
        raw_payload = request.data.decode("utf-8") if request.data else "{}"
        captured["payload"] = json.loads(raw_payload)
        return _FakeHTTPResponse(
            {
                "number": 42,
                "html_url": "https://github.com/seanbetts/sidebar/issues/42",
                "title": "[Bug] Unable to rename task",
            }
        )

    monkeypatch.setattr(settings, "github_issues_owner", "seanbetts")
    monkeypatch.setattr(settings, "github_issues_repo", "sidebar")
    monkeypatch.setattr(settings, "github_issues_token", "github_pat_test")
    monkeypatch.setattr(settings, "github_issues_api_base", "https://api.github.com")
    monkeypatch.setattr(github_issue_service, "urlopen", fake_urlopen)

    result = GitHubIssueService.submit_feedback_issue(
        issue_type="bug",
        summary="Unable to rename task",
        details="Rename fails when the task title includes emoji.",
        user_id="user-1",
        user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        conversation_id="conv-1",
        user_message_id="msg-1",
    )

    assert result["issue_number"] == 42
    assert result["issue_url"] == "https://github.com/seanbetts/sidebar/issues/42"
    assert result["labels_applied"] == ["bug"]
    assert result["platform"] == "iOS"
    assert captured["url"] == "https://api.github.com/repos/seanbetts/sidebar/issues"
    assert captured["payload"] == {
        "title": "[Bug] Unable to rename task",
        "body": captured["payload"]["body"],
        "labels": ["bug"],
    }
    assert "unable to rename task" in str(captured["payload"]["body"]).lower()


def test_submit_feedback_issue_requires_config(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "github_issues_owner", "")
    monkeypatch.setattr(settings, "github_issues_repo", "sidebar")
    monkeypatch.setattr(settings, "github_issues_token", "github_pat_test")

    with pytest.raises(ValueError, match="GitHub issue submission is not configured"):
        GitHubIssueService.submit_feedback_issue(
            issue_type="feature",
            summary="Recurring notes",
            user_id="user-1",
        )


def test_submit_feedback_issue_retries_without_labels_on_validation_error(
    monkeypatch: pytest.MonkeyPatch,
):
    captured_payloads: list[dict] = []
    call_count = {"value": 0}

    def fake_urlopen(request, timeout=15):
        del timeout
        raw_payload = request.data.decode("utf-8") if request.data else "{}"
        payload = json.loads(raw_payload)
        captured_payloads.append(payload)
        call_count["value"] += 1

        if call_count["value"] == 1:
            error_payload = json.dumps(
                {
                    "message": "Validation Failed",
                    "errors": [
                        {"resource": "Issue", "field": "labels", "code": "invalid"}
                    ],
                }
            ).encode("utf-8")
            raise HTTPError(
                url=request.full_url,
                code=422,
                msg="Unprocessable Entity",
                hdrs=None,
                fp=io.BytesIO(error_payload),
            )

        return _FakeHTTPResponse(
            {
                "number": 88,
                "html_url": "https://github.com/seanbetts/sidebar/issues/88",
                "title": "[Feature] Recurring notes",
            }
        )

    monkeypatch.setattr(settings, "github_issues_owner", "seanbetts")
    monkeypatch.setattr(settings, "github_issues_repo", "sidebar")
    monkeypatch.setattr(settings, "github_issues_token", "github_pat_test")
    monkeypatch.setattr(settings, "github_issues_api_base", "https://api.github.com")
    monkeypatch.setattr(github_issue_service, "urlopen", fake_urlopen)

    result = GitHubIssueService.submit_feedback_issue(
        issue_type="feature",
        summary="Recurring notes",
        details="Allow repeating reminders for notes.",
        user_id="user-1",
    )

    assert result["issue_number"] == 88
    assert result["labels_applied"] == []
    assert len(captured_payloads) == 2
    assert "labels" in captured_payloads[0]
    assert "labels" not in captured_payloads[1]


def test_submit_feedback_issue_404_includes_repository_guidance(
    monkeypatch: pytest.MonkeyPatch,
):
    def fake_urlopen(request, timeout=15):
        del timeout
        error_payload = json.dumps({"message": "Not Found"}).encode("utf-8")
        raise HTTPError(
            url=request.full_url,
            code=404,
            msg="Not Found",
            hdrs=None,
            fp=io.BytesIO(error_payload),
        )

    monkeypatch.setattr(settings, "github_issues_owner", "new-org")
    monkeypatch.setattr(settings, "github_issues_repo", "sidebar")
    monkeypatch.setattr(settings, "github_issues_token", "github_pat_test")
    monkeypatch.setattr(settings, "github_issues_api_base", "https://api.github.com")
    monkeypatch.setattr(github_issue_service, "urlopen", fake_urlopen)

    with pytest.raises(ValueError) as exc_info:
        GitHubIssueService.submit_feedback_issue(
            issue_type="bug",
            summary="Issue create fails",
            details="API call returns 404.",
            user_id="user-1",
        )

    message = str(exc_info.value)
    assert "GitHub issue creation failed (404): Not Found" in message
    assert "Repository 'new-org/sidebar' was not found or the token cannot access it" in message
