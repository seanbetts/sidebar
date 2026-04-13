"""Tests for backend/scripts/sentry_diagnostics.py."""

from __future__ import annotations

from scripts.sentry_diagnostics import build_sentry_summary, _fetch_releases


def test_summary_warns_when_unresolved_issues_exist() -> None:
    """Recent unresolved issues should elevate the Sentry summary."""
    result = build_sentry_summary(
        issues=[
            {
                "id": "1",
                "count": "12",
                "metadata": {"title": "ExampleError"},
            }
        ],
        events=[{"eventID": "abc123"}],
        releases=[{"version": "1.0.0"}],
    )

    assert result["status"] == "warn"
    assert result["data"]["unresolved_issue_count"] == 1
    assert result["warnings"]


def test_summary_stays_ok_when_issue_list_is_empty() -> None:
    """No unresolved issues should keep the Sentry summary healthy."""
    result = build_sentry_summary(
        issues=[],
        events=[{"eventID": "abc123"}],
        releases=[{"version": "1.0.0"}],
    )

    assert result["status"] == "ok"
    assert result["warnings"] == []


def test_summary_surfaces_release_warning_without_failing_summary() -> None:
    """Release fetch problems should stay visible in the summary output."""
    result = build_sentry_summary(
        issues=[],
        events=[{"eventID": "abc123"}],
        releases=[],
        release_warning="release data unavailable (HTTP 403: forbidden)",
    )

    assert result["status"] == "ok"
    assert result["data"]["release_count"] == 0
    assert result["warnings"] == ["release data unavailable (HTTP 403: forbidden)"]


def test_fetch_releases_filters_org_results_to_requested_project() -> None:
    """Organization releases should be filtered locally by project slug."""

    class DummyResponse:
        def __init__(self) -> None:
            self.status_code = 200

        def raise_for_status(self) -> None:
            return None

        def json(self) -> list[dict[str, object]]:
            return [
                {
                    "version": "1.0.0",
                    "projects": [{"slug": "silent-firefly-2603"}],
                },
                {
                    "version": "2.0.0",
                    "projects": [{"slug": "other-project"}],
                },
            ]

    class DummySession:
        def __init__(self) -> None:
            self.calls: list[dict[str, object]] = []

        def get(self, url: str, params: dict[str, object], timeout: int) -> DummyResponse:
            self.calls.append({"url": url, "params": params, "timeout": timeout})
            return DummyResponse()

    session = DummySession()

    releases = _fetch_releases(session, "sean-betts", "silent-firefly-2603")

    assert releases == [
        {
            "version": "1.0.0",
            "projects": [{"slug": "silent-firefly-2603"}],
        }
    ]
    assert session.calls == [
        {
            "url": "https://sentry.io/api/0/organizations/sean-betts/releases/",
            "params": {"per_page": 25},
            "timeout": 15,
        }
    ]
