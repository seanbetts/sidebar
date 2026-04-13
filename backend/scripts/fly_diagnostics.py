#!/usr/bin/env python3
"""Read-only Fly.io diagnostics for app status, machines, and logs."""

from __future__ import annotations

import argparse
import json
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


FLY_MACHINES_API = "https://api.machines.dev/v1"
FLY_API = "https://api.fly.io/api/v1"


def build_fly_summary(
    *,
    app: dict[str, Any],
    machines: list[dict[str, Any]],
    logs: list[dict[str, Any]],
) -> dict[str, object]:
    """Build the top-level Fly summary payload."""
    warnings: list[str] = []
    status = "ok"
    if str(app.get("status", "")).lower() not in {"deployed", "running"}:
        status = "warn"
        warnings.append("app status is not healthy")
    if any(int(machine.get("restart_count", 0)) > 0 for machine in machines):
        status = "warn"
        warnings.append("machines have recent restarts")
    if logs:
        status = "warn"
        warnings.append("recent error logs detected")

    return build_result(
        target="fly",
        command="summary",
        status=status,
        data={
            "app_status": app.get("status"),
            "machine_count": len(machines),
            "error_log_count": len(logs),
        },
        warnings=warnings,
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Fly.io diagnostics.")
    parser.add_argument(
        "command",
        nargs="?",
        default="summary",
        choices=["summary", "status", "deploys", "machines", "logs"],
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    load_local_env()
    args = parse_args(argv)
    missing = [
        name
        for name in ("OPS_FLY_API_TOKEN", "OPS_FLY_APP")
        if not os.environ.get(name, "").strip()
    ]
    if missing:
        result = config_error_result(
            target="fly",
            command=args.command,
            missing_vars=missing,
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_CONFIG

    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {os.environ['OPS_FLY_API_TOKEN']}",
            "Accept": "application/json",
        }
    )
    app_name = os.environ["OPS_FLY_APP"]
    region = os.environ.get("OPS_FLY_REGION", "").strip()

    try:
        if args.command == "summary":
            app = _fetch_app(session, app_name)
            machines = _fetch_machines(session, app_name)
            try:
                logs = _fetch_logs(session, app_name, region=region)
            except Exception:
                logs = []
            result = build_fly_summary(app=app, machines=machines, logs=logs)
        elif args.command == "status":
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={"app": _fetch_app(session, app_name)},
            )
        elif args.command == "deploys":
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={"deploys": _build_deploy_rows(_fetch_machines(session, app_name))},
            )
        elif args.command == "machines":
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={"machines": _fetch_machines(session, app_name)},
            )
        else:
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={"logs": _fetch_logs(session, app_name, region=region)},
            )
    except Exception as exc:
        result = build_result(
            target="fly",
            command=args.command,
            status="error",
            errors=[str(exc)],
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_FAILURE

    _print_result(result, as_json=args.as_json)
    return EXIT_OK


def _fetch_app(session: requests.Session, app_name: str) -> dict[str, Any]:
    response = session.get(
        f"{FLY_MACHINES_API}/apps/{app_name}",
        timeout=15,
    )
    response.raise_for_status()
    return dict(response.json())


def _fetch_machines(session: requests.Session, app_name: str) -> list[dict[str, Any]]:
    response = session.get(
        f"{FLY_MACHINES_API}/apps/{app_name}/machines",
        timeout=15,
    )
    response.raise_for_status()
    machines = response.json()
    if isinstance(machines, list):
        return [dict(machine) for machine in machines]
    return []


def _fetch_logs(
    session: requests.Session,
    app_name: str,
    *,
    region: str,
) -> list[dict[str, Any]]:
    params: dict[str, str] = {}
    if region:
        params["region"] = region
    response = session.get(
        f"{FLY_API}/apps/{app_name}/logs",
        params=params,
        timeout=15,
    )
    response.raise_for_status()
    return _parse_log_lines(response.text)


def _parse_log_lines(payload: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for raw_line in payload.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            if "error" in line.lower() or "warn" in line.lower():
                rows.append({"level": "error", "message": line})
            continue
        if str(parsed.get("level", "")).lower() in {"error", "warn", "warning"}:
            rows.append(dict(parsed))
    return rows


def _build_deploy_rows(machines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for machine in machines:
        config = machine.get("config") or {}
        image = config.get("image") or machine.get("image_ref")
        rows.append(
            {
                "id": machine.get("id"),
                "state": machine.get("state"),
                "image": image,
                "updated_at": machine.get("updated_at"),
            }
        )
    return rows


def _print_result(result: dict[str, object], *, as_json: bool) -> None:
    if as_json:
        print_json_result(result)
        return
    print_text_result(result)


if __name__ == "__main__":
    raise SystemExit(main())
