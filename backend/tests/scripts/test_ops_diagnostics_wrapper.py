"""Tests for scripts/ops-diagnostics.sh."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "ops-diagnostics.sh"


def test_wrapper_reports_missing_db_url_for_db_target(tmp_path: Path) -> None:
    """DB target should fail cleanly when OPS_DB_URL is missing."""
    env = _base_env(tmp_path)
    env.pop("OPS_DB_URL", None)

    result = subprocess.run(
        ["bash", str(SCRIPT_PATH), "db", "summary"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 2
    assert "OPS_DB_URL" in result.stdout


def test_wrapper_forwards_json_flag_to_backend_command(tmp_path: Path) -> None:
    """Wrapper should forward extra CLI args to the selected backend command."""
    env = _env_with_fake_runner(tmp_path)
    env["OPS_DB_URL"] = "postgresql://user:pass@example.com:6543/postgres"

    result = subprocess.run(
        ["bash", str(SCRIPT_PATH), "db", "summary", "--json"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "--json" in (tmp_path / "invocations.log").read_text(encoding="utf-8")


def test_wrapper_forwards_db_sql_file_arguments(tmp_path: Path) -> None:
    """Wrapper should pass db sql file arguments through to db_diagnostics.py."""
    env = _env_with_fake_runner(tmp_path)
    env["OPS_DB_URL"] = "postgresql://user:pass@example.com:6543/postgres"
    sql_file = tmp_path / "query.sql"
    sql_file.write_text("select 1\n", encoding="utf-8")

    result = subprocess.run(
        [
            "bash",
            str(SCRIPT_PATH),
            "db",
            "sql",
            "--file",
            str(sql_file),
            "--json",
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    invocation_log = (tmp_path / "invocations.log").read_text(encoding="utf-8")
    assert result.returncode == 0
    assert "db_diagnostics.py sql --file" in invocation_log
    assert str(sql_file) in invocation_log
    assert "--json" in invocation_log


def test_wrapper_all_runs_all_targets_without_aborting_on_failure(tmp_path: Path) -> None:
    """All mode should keep going when one backend command fails."""
    env = _env_with_fake_runner(tmp_path)
    env.update(
        {
            "OPS_DB_URL": "postgresql://user:pass@example.com:6543/postgres",
            "OPS_SENTRY_AUTH_TOKEN": "token",
            "OPS_SENTRY_ORG": "org",
            "OPS_SENTRY_PROJECT": "project",
            "OPS_FLY_API_TOKEN": "fly-token",
            "OPS_FLY_APP": "sidebar",
            "OPS_DIAGNOSTICS_FAIL_TARGET": "sentry_diagnostics.py",
        }
    )

    result = subprocess.run(
        ["bash", str(SCRIPT_PATH), "all"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    invocation_log = (tmp_path / "invocations.log").read_text(encoding="utf-8")
    assert "db_diagnostics.py" in invocation_log
    assert "app_diagnostics.py" in invocation_log
    assert "sentry_diagnostics.py" in invocation_log
    assert "fly_diagnostics.py" in invocation_log
    assert result.returncode == 1
    assert "sentry" in result.stdout


def _base_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["TMPDIR"] = str(tmp_path)
    env["HOME"] = str(tmp_path)
    env["OPS_DIAGNOSTICS_SKIP_ENV_LOAD"] = "1"
    return env


def _env_with_fake_runner(tmp_path: Path) -> dict[str, str]:
    fake_python = tmp_path / "fake-python.sh"
    fake_python.write_text(
        """#!/bin/bash
script="$1"
shift
echo "$(basename "$script") $*" >> "$TMPDIR/invocations.log"
if [[ "$(basename "$script")" == "${OPS_DIAGNOSTICS_FAIL_TARGET:-}" ]]; then
  echo "simulated failure for $(basename "$script")"
  exit 1
fi
echo "simulated success for $(basename "$script")"
exit 0
""",
        encoding="utf-8",
    )
    fake_python.chmod(0o755)
    env = _base_env(tmp_path)
    env["OPS_DIAGNOSTICS_PYTHON"] = str(fake_python)
    return env
