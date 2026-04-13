#!/usr/bin/env python3
"""Read-only Sentry diagnostics for issues, events, and releases."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

import requests

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from scripts.ops_diagnostics_common import (  # noqa: E402
    EXIT_CONFIG,
    EXIT_FAILURE,
    EXIT_OK,
    build_result,
    config_error_result,
    load_local_env,
    print_json_result,
    print_text_result,
)


SENTRY_BASE_URL = "https://sentry.io/api/0"
RELEASE_PAGE_SIZE = 25


def build_sentry_summary(
    *,
    issues: list[dict[str, Any]],
    events: list[dict[str, Any]],
    releases: list[dict[str, Any]],
    release_warning: str | None = None,
) -> dict[str, object]:
    """Build the top-level Sentry summary payload."""
    warnings: list[str] = []
    status = "ok"
    if issues:
        status = "warn"
        warnings.append("unresolved issues detected")
    if release_warning:
        warnings.append(release_warning)

    return build_result(
        target="sentry",
        command="summary",
        status=status,
        data={
            "unresolved_issue_count": len(issues),
            "recent_event_count": len(events),
            "release_count": len(releases),
        },
        warnings=warnings,
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Sentry diagnostics.")
    parser.add_argument(
        "command",
        nargs="?",
        default="summary",
        choices=["summary", "issues", "events", "releases"],
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    load_local_env()
    args = parse_args(argv)
    missing = [
        name
        for name in ("OPS_SENTRY_AUTH_TOKEN", "OPS_SENTRY_ORG", "OPS_SENTRY_PROJECT")
        if not os.environ.get(name, "").strip()
    ]
    if missing:
        result = config_error_result(
            target="sentry",
            command=args.command,
            missing_vars=missing,
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_CONFIG

    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {os.environ['OPS_SENTRY_AUTH_TOKEN']}",
            "Accept": "application/json",
        }
    )
    org = os.environ["OPS_SENTRY_ORG"]
    project = os.environ["OPS_SENTRY_PROJECT"]

    try:
        if args.command == "summary":
            issues = _fetch_issues(session, org, project)
            events = _fetch_events(session, org, project)
            releases: list[dict[str, Any]] = []
            release_warning: str | None = None
            try:
                releases = _fetch_releases(session, org, project)
            except Exception as exc:
                release_warning = _format_release_fetch_error(exc)
            result = build_sentry_summary(
                issues=issues,
                events=events,
                releases=releases,
                release_warning=release_warning,
            )
        elif args.command == "issues":
            result = build_result(
                target="sentry",
                command=args.command,
                status="ok",
                data={"issues": _fetch_issues(session, org, project)},
            )
        elif args.command == "events":
            result = build_result(
                target="sentry",
                command=args.command,
                status="ok",
                data={"events": _fetch_events(session, org, project)},
            )
        else:
            result = build_result(
                target="sentry",
                command=args.command,
                status="ok",
                data={"releases": _fetch_releases(session, org, project)},
            )
    except Exception as exc:
        result = build_result(
            target="sentry",
            command=args.command,
            status="error",
            errors=[str(exc)],
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_FAILURE

    _print_result(result, as_json=args.as_json)
    return EXIT_OK


def _fetch_issues(
    session: requests.Session,
    org: str,
    project: str,
) -> list[dict[str, Any]]:
    response = session.get(
        f"{SENTRY_BASE_URL}/projects/{org}/{project}/issues/",
        params={"query": "is:unresolved", "limit": 10, "statsPeriod": "24h"},
        timeout=15,
    )
    response.raise_for_status()
    return list(response.json())


def _fetch_events(
    session: requests.Session,
    org: str,
    project: str,
) -> list[dict[str, Any]]:
    response = session.get(
        f"{SENTRY_BASE_URL}/projects/{org}/{project}/events/",
        params={"limit": 10, "statsPeriod": "24h"},
        timeout=15,
    )
    response.raise_for_status()
    return list(response.json())


def _fetch_releases(
    session: requests.Session,
    org: str,
    project: str,
) -> list[dict[str, Any]]:
    response = session.get(
        f"{SENTRY_BASE_URL}/organizations/{org}/releases/",
        params={"per_page": RELEASE_PAGE_SIZE},
        timeout=15,
    )
    response.raise_for_status()
    releases = list(response.json())
    return [
        release
        for release in releases
        if _release_includes_project(release, project)
    ]


def _release_includes_project(release: dict[str, Any], project: str) -> bool:
    target = str(project)
    for project_data in release.get("projects", []):
        slug = str(project_data.get("slug", ""))
        project_id = str(project_data.get("id", ""))
        if slug == target or project_id == target:
            return True
    return False


def _format_release_fetch_error(exc: Exception) -> str:
    if isinstance(exc, requests.HTTPError) and exc.response is not None:
        response = exc.response
        detail = _response_error_detail(response)
        if detail:
            return (
                f"release data unavailable "
                f"(HTTP {response.status_code}: {detail})"
            )
        return f"release data unavailable (HTTP {response.status_code})"
    return "release data unavailable"


def _response_error_detail(response: requests.Response) -> str | None:
    try:
        payload = response.json()
    except ValueError:
        text = response.text.strip()
        return text or None

    detail = payload.get("detail")
    if isinstance(detail, str) and detail.strip():
        return detail.strip()
    return None


def _print_result(result: dict[str, object], *, as_json: bool) -> None:
    if as_json:
        print_json_result(result)
        return
    print_text_result(result)


if __name__ == "__main__":
    raise SystemExit(main())
