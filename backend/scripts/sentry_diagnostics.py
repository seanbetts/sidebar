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


def build_sentry_summary(
    *,
    issues: list[dict[str, Any]],
    events: list[dict[str, Any]],
    releases: list[dict[str, Any]] | None,
) -> dict[str, object]:
    """Build the top-level Sentry summary payload."""
    warnings: list[str] = []
    status = "ok"
    if issues:
        status = "warn"
        warnings.append("unresolved issues detected")
    if releases is None:
        warnings.append("release data unavailable")

    return build_result(
        target="sentry",
        command="summary",
        status=status,
        data={
            "unresolved_issue_count": len(issues),
            "recent_event_count": len(events),
            "release_count": len(releases or []),
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
            try:
                releases = _fetch_releases(session, org, project)
            except Exception:
                releases = None
            result = build_sentry_summary(
                issues=issues,
                events=events,
                releases=releases,
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
        params={"project": project, "per_page": 10},
        timeout=15,
    )
    response.raise_for_status()
    return list(response.json())


def _print_result(result: dict[str, object], *, as_json: bool) -> None:
    if as_json:
        print_json_result(result)
        return
    print_text_result(result)


if __name__ == "__main__":
    raise SystemExit(main())
