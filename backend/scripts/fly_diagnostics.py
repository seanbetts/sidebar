#!/usr/bin/env python3
"""Read-only Fly.io diagnostics for app status, machines, and logs."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections.abc import Mapping
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
_EXPECTED_PROCESS_GROUPS = ("app", "notification", "website", "ingestion")
_UNRECOGNIZED_PROCESS_GROUP = "unrecognized"
_DEMAND_MACHINE_STATES = {"started", "starting", "stopping", "stopped", "suspended"}
_NOTIFICATION_ACTIVE_STATES = {"started", "starting"}
_SAFE_FAILURE_MESSAGE = "Fly diagnostics request failed."
_CREDENTIAL_ASSIGNMENT_PATTERN = re.compile(
    r"""(?ix)
    [\"']?(?:authorization|proxy-authorization|api[_-]?key|access[_-]?token|
    token|secret(?:[_-]?\w*)?|password|credential)[\"']?
    \s*[:=]\s*(?:
        \"(?:bearer\s+)?[^\"]*\"
        | '(?:bearer\s+)?[^']*'
        | (?:bearer\s+)?[^\s,;}\]]+
    )
    """
)
_BEARER_PATTERN = re.compile(r"\bbearer\s+[\"']?[^\s,;}\]\"']+[\"']?", re.IGNORECASE)
_JSON_UNICODE_HEX_DIGITS = frozenset("0123456789abcdefABCDEF")
_CREDENTIAL_UNICODE_CHARACTERS = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 \t\r\n\"'=:_-"
)
_QUOTED_CREDENTIAL_PATTERN = re.compile(
    r"""(?x)
    ([\"'])
    (?:
        (?:sk|pk|rk|ghp|github_pat|flyv1)[_-][A-Za-z0-9._~+/=-]{8,}
        | eyJ[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2}
        | [A-Za-z0-9._~+/=-]{20,}
    )
    \1
    """
)


def build_fly_summary(
    *,
    app: dict[str, Any],
    machines: list[dict[str, Any]],
    logs: list[dict[str, Any]],
) -> dict[str, object]:
    """Build the top-level Fly summary payload."""
    process_groups, topology_is_valid = _build_process_groups(machines)
    warnings: list[str] = []
    if not topology_is_valid:
        warnings.append("machine topology is invalid")
    notification_rows = process_groups["notification"]
    if (
        len(notification_rows) == 1
        and notification_rows[0]["state"] not in _NOTIFICATION_ACTIVE_STATES
    ):
        warnings.append("notification control machine is not active")
    if any(_restart_count(machine) > 0 for machine in machines):
        warnings.append("machines have recent restarts")
    if logs:
        warnings.append("recent error logs detected")

    return build_result(
        target="fly",
        command="summary",
        status="warn" if warnings else "ok",
        data={
            "app_status": _safe_optional_text(app.get("status"))[0],
            "machine_count": len(machines),
            "error_log_count": len(logs),
            "process_groups": process_groups,
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
    session.headers.update({"Accept": "application/json"})
    token = os.environ["OPS_FLY_API_TOKEN"]
    app_name = os.environ["OPS_FLY_APP"]
    region = os.environ.get("OPS_FLY_REGION", "").strip()

    try:
        if args.command == "summary":
            app = _fetch_app(session, app_name, token=token)
            machines = _fetch_machines(session, app_name, token=token)
            try:
                logs = _fetch_logs(session, app_name, region=region, token=token)
            except Exception:
                logs = []
            result = build_fly_summary(app=app, machines=machines, logs=logs)
        elif args.command == "status":
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={
                    "app": _build_app_row(_fetch_app(session, app_name, token=token))
                },
            )
        elif args.command == "deploys":
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={
                    "deploys": _build_deploy_rows(
                        _fetch_machines(session, app_name, token=token)
                    )
                },
            )
        elif args.command == "machines":
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={
                    "machines": _build_machine_rows(
                        _fetch_machines(session, app_name, token=token)
                    )
                },
            )
        else:
            result = build_result(
                target="fly",
                command=args.command,
                status="ok",
                data={
                    "logs": _build_log_rows(
                        _fetch_logs(session, app_name, region=region, token=token)
                    )
                },
            )
    except Exception:
        result = build_result(
            target="fly",
            command=args.command,
            status="error",
            errors=[_safe_error_message()],
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_FAILURE

    _print_result(result, as_json=args.as_json)
    return EXIT_OK


def _auth_headers(token: str, *, use_bearer: bool) -> dict[str, str]:
    """Build endpoint-specific Fly auth headers."""
    if use_bearer:
        return {"Authorization": f"Bearer {token}"}
    return {"Authorization": token}


def _fetch_app(
    session: requests.Session, app_name: str, *, token: str
) -> dict[str, Any]:
    response = session.get(
        f"{FLY_MACHINES_API}/apps/{app_name}",
        headers=_auth_headers(token, use_bearer=True),
        timeout=15,
    )
    response.raise_for_status()
    return dict(response.json())


def _fetch_machines(
    session: requests.Session, app_name: str, *, token: str
) -> list[dict[str, Any]]:
    response = session.get(
        f"{FLY_MACHINES_API}/apps/{app_name}/machines",
        headers=_auth_headers(token, use_bearer=True),
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
    token: str,
) -> list[dict[str, Any]]:
    params: dict[str, str] = {}
    if region:
        params["region"] = region
    response = session.get(
        f"{FLY_API}/apps/{app_name}/logs",
        headers=_auth_headers(token, use_bearer=False),
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
                rows.append(
                    {"level": "error", "message": _sanitize_diagnostic_text(line)}
                )
            continue
        if isinstance(parsed, Mapping) and str(parsed.get("level", "")).lower() in {
            "error",
            "warn",
            "warning",
        }:
            rows.extend(_build_log_rows([dict(parsed)]))
    return rows


def _build_process_groups(
    machines: list[dict[str, Any]],
) -> tuple[dict[str, list[dict[str, object]]], bool]:
    """Group redacted Machine rows and validate the expected Fly topology."""
    process_groups: dict[str, list[dict[str, object]]] = {
        group: [] for group in _EXPECTED_PROCESS_GROUPS
    }
    process_groups[_UNRECOGNIZED_PROCESS_GROUP] = []
    for machine in machines:
        row, projection_is_valid = _project_machine_row(machine)
        process_group = row["process_group"]
        demand_state_is_valid = (
            process_group not in {"app", "website", "ingestion"}
            or row["state"] in _DEMAND_MACHINE_STATES
        )
        if (
            not projection_is_valid
            or process_group not in _EXPECTED_PROCESS_GROUPS
            or not demand_state_is_valid
        ):
            process_groups[_UNRECOGNIZED_PROCESS_GROUP].append(row)
        else:
            process_groups[process_group].append(row)

    expected_groups_present = all(
        len(process_groups[group]) == 1 for group in _EXPECTED_PROCESS_GROUPS
    )
    return (
        process_groups,
        expected_groups_present and not process_groups[_UNRECOGNIZED_PROCESS_GROUP],
    )


def _build_machine_rows(machines: list[dict[str, Any]]) -> list[dict[str, object]]:
    """Return the approved, credential-free columns for each Fly Machine."""
    return [_project_machine_row(machine)[0] for machine in machines]


def _build_machine_row(machine: Mapping[str, Any]) -> dict[str, object]:
    """Return one redacted Fly Machine row with stable approved fields only."""
    return _project_machine_row(machine)[0]


def _project_machine_row(
    machine: Mapping[str, Any],
) -> tuple[dict[str, object], bool]:
    """Project one Machine and report whether its controlled fields are well formed."""
    config = _mapping(machine.get("config"))
    guest = _mapping(config.get("guest"))
    machine_id, id_is_valid = _safe_required_text(machine.get("id"))
    process_group, group_is_valid = _safe_required_text(_process_group(machine))
    state, state_is_valid = _safe_required_text(machine.get("state"))
    region, region_is_valid = _safe_optional_text(machine.get("region"))
    memory_mb, memory_is_valid = _safe_optional_number(guest.get("memory_mb"))
    restart_count, restart_is_valid = _safe_restart_count(machine.get("restart_count"))
    updated_at, updated_at_is_valid = _safe_optional_text(machine.get("updated_at"))
    row: dict[str, object] = {
        "id": machine_id,
        "process_group": process_group,
        "state": state,
        "region": region,
        "memory_mb": memory_mb,
        "restart_count": restart_count,
        "updated_at": updated_at,
    }
    return (
        row,
        id_is_valid
        and group_is_valid
        and state_is_valid
        and region_is_valid
        and memory_is_valid
        and restart_is_valid
        and updated_at_is_valid,
    )


def _build_app_row(app: Mapping[str, Any]) -> dict[str, object]:
    """Return the public app identity and state without response metadata."""
    return {
        "name": _safe_optional_text(app.get("name"))[0],
        "status": _safe_optional_text(app.get("status"))[0],
    }


def _build_log_rows(logs: list[dict[str, Any]]) -> list[dict[str, object]]:
    """Return credential-free log rows suitable for diagnostic output."""
    return [
        {
            "level": _safe_optional_text(log.get("level"))[0],
            "message": _sanitize_diagnostic_text(log.get("message")),
        }
        for log in logs
    ]


def _sanitize_diagnostic_text(value: object) -> str | None:
    """Redact credentials from all diagnostic text before it reaches output."""
    if not isinstance(value, str):
        return None
    unicode_normalized = _normalize_json_credential_escapes(value)
    normalized = _normalize_escaped_quotes(unicode_normalized)
    without_assignments = _CREDENTIAL_ASSIGNMENT_PATTERN.sub("[REDACTED]", normalized)
    without_bearer = _BEARER_PATTERN.sub("[REDACTED]", without_assignments)
    return _QUOTED_CREDENTIAL_PATTERN.sub("[REDACTED]", without_bearer)


def _normalize_escaped_quotes(value: str) -> str:
    """Collapse escaped quote delimiters in O(n) time and O(n) output space."""
    fragments: list[str] = []
    position = 0
    while position < len(value):
        slash_start = value.find("\\", position)
        if slash_start == -1:
            fragments.append(value[position:])
            break
        fragments.append(value[position:slash_start])

        slash_end = slash_start
        while slash_end < len(value) and value[slash_end] == "\\":
            slash_end += 1
        if slash_end < len(value) and value[slash_end] in {'"', "'"}:
            fragments.append(value[slash_end])
            position = slash_end + 1
            continue
        fragments.append(value[slash_start:slash_end])
        position = slash_end
    return "".join(fragments)


def _normalize_json_credential_escapes(value: str) -> str:
    """Decode credential Unicode chains in O(n) time and O(n) output space.

    The cursor advances past every scanned span, so no chain suffix is revisited.
    The disjoint output fragments and their joined result are bounded by input size.
    """
    fragments: list[str] = []
    position = 0
    while position < len(value):
        chain_start = value.find("\\", position)
        if chain_start == -1:
            fragments.append(value[position:])
            break
        fragments.append(value[position:chain_start])

        unicode_position = chain_start
        while unicode_position < len(value) and value[unicode_position] == "\\":
            unicode_position += 1
        parsed = _parse_json_unicode_escape(value, unicode_position)
        if parsed is None:
            fragments.append(value[chain_start:unicode_position])
            position = unicode_position
            continue

        replacement, position = _collapse_json_unicode_escape_chain(
            value,
            start=chain_start,
            character=parsed[0],
            chain_end=parsed[1],
        )
        fragments.append(replacement)
    return "".join(fragments)


def _collapse_json_unicode_escape_chain(
    value: str,
    *,
    start: int,
    character: str,
    chain_end: int,
) -> tuple[str, int]:
    """Scan one chain once and return its safe replacement and exclusive end."""
    while character == "\\":
        continuation_position = chain_end
        while (
            continuation_position < len(value) and value[continuation_position] == "\\"
        ):
            continuation_position += 1
        parsed = _parse_json_unicode_escape(value, continuation_position)
        if parsed is None:
            return value[start:continuation_position], continuation_position
        character, chain_end = parsed

    if character in _CREDENTIAL_UNICODE_CHARACTERS:
        return character, chain_end
    return value[start:chain_end], chain_end


def _parse_json_unicode_escape(value: str, position: int) -> tuple[str, int] | None:
    """Parse one case-insensitive ``uXXXX`` token without decoding other syntax."""
    end = position + 5
    if end > len(value) or value[position : position + 1] not in {"u", "U"}:
        return None
    code_point = value[position + 1 : end]
    if len(code_point) != 4 or any(
        character not in _JSON_UNICODE_HEX_DIGITS for character in code_point
    ):
        return None
    return chr(int(code_point, 16)), end


def _safe_error_message() -> str:
    """Return the fixed Fly failure text without reading an exception value."""
    return _sanitize_diagnostic_text(_SAFE_FAILURE_MESSAGE) or "[REDACTED]"


def _safe_required_text(value: object) -> tuple[str | None, bool]:
    """Return one non-empty safe string and whether the source was well formed."""
    text, is_valid = _safe_optional_text(value)
    return text, is_valid and bool(text)


def _safe_optional_text(value: object) -> tuple[str | None, bool]:
    """Return a safe scalar string or none without copying malformed response data."""
    if value is None:
        return None, True
    if not isinstance(value, str):
        return None, False
    sanitized = _sanitize_diagnostic_text(value)
    if sanitized != value:
        return None, False
    return value, True


def _safe_optional_number(value: object) -> tuple[int | None, bool]:
    """Return a non-negative integer or none without copying malformed response data."""
    if value is None:
        return None, True
    if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
        return value, True
    if isinstance(value, str) and value.isdecimal():
        return int(value), True
    return None, False


def _safe_restart_count(value: object) -> tuple[int, bool]:
    """Return a non-negative restart count, defaulting malformed data to zero."""
    if value is None:
        return 0, True
    if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
        return value, True
    if isinstance(value, str) and value.isdecimal():
        return int(value), True
    return 0, False


def _process_group(machine: Mapping[str, Any]) -> str | None:
    """Resolve Fly group metadata using FlyMachineService's precedence order."""
    config = _mapping(machine.get("config"))
    metadata = _mapping(config.get("metadata"))
    env = _mapping(config.get("env"))
    process_group = (
        machine.get("process_group")
        or metadata.get("fly_process_group")
        or env.get("FLY_PROCESS_GROUP")
    )
    return process_group if isinstance(process_group, str) else None


def _mapping(value: object) -> Mapping[str, Any]:
    """Return a mapping response fragment or an empty mapping for malformed data."""
    if isinstance(value, Mapping):
        return value
    return {}


def _restart_count(machine: Mapping[str, Any]) -> int:
    """Return a non-negative integer restart count without trusting malformed payloads."""
    return _safe_restart_count(machine.get("restart_count"))[0]


def _build_deploy_rows(machines: list[dict[str, Any]]) -> list[dict[str, object]]:
    """Return safe deploy rows without raw Machine configuration data."""
    rows: list[dict[str, object]] = []
    for machine in machines:
        config = _mapping(machine.get("config"))
        image = config.get("image") or machine.get("image_ref")
        rows.append(
            {
                "id": _safe_optional_text(machine.get("id"))[0],
                "state": _safe_optional_text(machine.get("state"))[0],
                "image": _safe_optional_text(image)[0],
                "updated_at": _safe_optional_text(machine.get("updated_at"))[0],
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
