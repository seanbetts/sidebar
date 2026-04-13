#!/usr/bin/env python3
"""Shared helpers for terminal-only ops diagnostics scripts."""

from __future__ import annotations

import json
import os
import sys
from datetime import UTC, date, datetime
from pathlib import Path
from typing import TextIO
from urllib.parse import urlparse
from uuid import UUID


EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_CONFIG = 2

_STATUS_RANK = {
    "ok": 0,
    "warn": 1,
    "error": 2,
    "unavailable": 3,
}


def load_local_env(repo_root: Path | None = None) -> None:
    """Load repo-local env files without overwriting existing values."""
    root = repo_root or Path(__file__).resolve().parents[2]
    backend_root = root / "backend"
    for path in (
        root / ".env.local",
        root / ".env",
        backend_root / ".env.local",
        backend_root / ".env",
    ):
        _load_env_file(path)


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def masked_url_summary(database_url: str) -> str:
    """Return a masked connection summary suitable for diagnostics output."""
    parsed = urlparse(database_url)
    host = parsed.hostname or "unknown"
    port = parsed.port or "unknown"
    database = (parsed.path or "/").lstrip("/") or "unknown"
    user = parsed.username or "unknown"
    return f"user={user} host={host} port={port} db={database}"


def build_result(
    *,
    target: str,
    command: str,
    status: str,
    data: dict[str, object] | None = None,
    warnings: list[str] | None = None,
    errors: list[str] | None = None,
    generated_at: str | None = None,
) -> dict[str, object]:
    """Build a shared JSON envelope for diagnostics output."""
    return {
        "target": target,
        "command": command,
        "status": status,
        "generated_at": generated_at or _now_iso(),
        "data": data or {},
        "warnings": warnings or [],
        "errors": errors or [],
    }


def print_json_result(result: dict[str, object], stream: TextIO | None = None) -> None:
    """Serialize a diagnostics result to JSON."""
    output = stream or sys.stdout
    json.dump(result, output, indent=2, sort_keys=True, default=_json_default)
    output.write("\n")


def print_text_result(result: dict[str, object], stream: TextIO | None = None) -> None:
    """Render a compact human-readable diagnostics result."""
    output = stream or sys.stdout
    output.write(
        f"[{result['status']}] {result['target']} {result['command']} "
        f"({result['generated_at']})\n"
    )
    data = result.get("data", {})
    if isinstance(data, dict):
        for key, value in data.items():
            output.write(f"- {key}: {value}\n")
    for warning in result.get("warnings", []):
        output.write(f"- warning: {warning}\n")
    for error in result.get("errors", []):
        output.write(f"- error: {error}\n")


def merge_statuses(*statuses: str) -> str:
    """Return the most severe status from the provided values."""
    filtered = [status for status in statuses if status]
    if not filtered:
        return "ok"
    return max(filtered, key=lambda status: _STATUS_RANK.get(status, 99))


def config_error_result(
    *,
    target: str,
    command: str,
    missing_vars: list[str],
) -> dict[str, object]:
    """Return a shared config-error payload."""
    return build_result(
        target=target,
        command=command,
        status="error",
        errors=[f"Missing environment variable: {name}" for name in missing_vars],
    )


def _now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat()


def _json_default(value: object) -> str:
    """Serialize common database scalar types for diagnostics JSON output."""
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    raise TypeError(f"Object of type {value.__class__.__name__} is not JSON serializable")
