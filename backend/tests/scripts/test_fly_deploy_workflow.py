"""Regression tests for the committed Fly deploy workflow."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
BACKEND_ROOT = REPO_ROOT / "backend"
FLY_DEPLOY_WORKFLOW_PATH = REPO_ROOT / "ci" / "workflows" / "fly-deploy.yml"
APP_MACHINE_ID = "d8d9510a295118"
NOTIFICATION_MACHINE_ID = "178114dc276891"
WEBSITE_MACHINE_ID = "e784079b707483"
INGESTION_MACHINE_ID = "3d8d40ff09d589"
ALTERNATE_NOTIFICATION_MACHINE_ID = "4b12c83f6a09de"
DUPLICATE_MACHINE_ID = "6e82d4c7273887"


def _workflow() -> dict[str, Any]:
    """Return the committed Fly deploy workflow payload."""
    return yaml.load(
        FLY_DEPLOY_WORKFLOW_PATH.read_text(encoding="utf-8"),
        Loader=yaml.BaseLoader,
    )


def _deploy_step(name: str) -> dict[str, Any]:
    """Return one named deploy step from the committed workflow."""
    steps = _workflow()["jobs"]["deploy"]["steps"]
    matching = [step for step in steps if step.get("name") == name]
    assert len(matching) == 1, f"Expected one workflow step named {name!r}"
    return matching[0]


def _verify_step(name: str) -> dict[str, Any]:
    """Return one named verification step from the committed workflow."""
    steps = _workflow()["jobs"]["verify"]["steps"]
    matching = [step for step in steps if step.get("name") == name]
    assert len(matching) == 1, f"Expected one verify step named {name!r}"
    return matching[0]


def test_fly_verifies_production_migration_paths_before_deploying() -> None:
    """Fly deployment must wait for migration-lineage and runner regressions."""
    step = _verify_step("Run deployment regression tests")
    command = step["run"]

    assert "tests/api/test_alembic_migration_lineage.py" in command
    assert "tests/scripts/test_run_production_migrations.py" in command
    assert "tests/scripts/test_fly_toml.py" in command


def _machine(
    machine_id: object,
    process_group: str,
    state: str,
    *,
    location: str = "metadata",
    region: object = "lhr",
) -> dict[str, object]:
    """Build a representative Fly Machine response."""
    machine: dict[str, object] = {
        "id": machine_id,
        "state": state,
        "region": region,
        "config": {},
    }
    if location == "top_level":
        machine["process_group"] = process_group
        machine["config"] = {
            "metadata": {"fly_process_group": "wrong-metadata"},
            "env": {"FLY_PROCESS_GROUP": "wrong-env"},
        }
    elif location == "metadata":
        machine["config"] = {
            "metadata": {"fly_process_group": process_group},
            "env": {"FLY_PROCESS_GROUP": "wrong-env"},
        }
    elif location == "env":
        machine["config"] = {"env": {"FLY_PROCESS_GROUP": process_group}}
    else:
        raise ValueError(f"Unsupported process-group location: {location}")
    return machine


def _healthy_topology(
    *,
    app_state: str = "started",
    notification_state: str = "started",
    website_state: str = "stopped",
    ingestion_state: str = "suspended",
    app_id: str = APP_MACHINE_ID,
    notification_id: str = NOTIFICATION_MACHINE_ID,
    website_id: str = WEBSITE_MACHINE_ID,
    ingestion_id: str = INGESTION_MACHINE_ID,
) -> list[dict[str, object]]:
    """Build all four groups using each supported metadata location."""
    return [
        _machine(app_id, "app", app_state, location="top_level"),
        _machine(
            notification_id,
            "notification",
            notification_state,
            location="metadata",
        ),
        _machine(website_id, "website", website_state, location="env"),
        _machine(ingestion_id, "ingestion", ingestion_state),
    ]


def _install_fake_flyctl(
    tmp_path: Path,
    snapshots: list[list[dict[str, object]]],
) -> tuple[Path, Path]:
    """Install a local Flyctl double that records commands and returns snapshots."""
    fixture_path = tmp_path / "machine-snapshots.json"
    fixture_path.write_text(json.dumps(snapshots), encoding="utf-8")
    calls_path = tmp_path / "flyctl-calls.jsonl"
    counter_path = tmp_path / "machine-list-count"
    executable = tmp_path / "flyctl"
    executable.write_text(
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with Path(os.environ["FAKE_FLYCTL_CALLS"]).open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(args) + "\\n")

if args == ["-c", "fly.toml", "machine", "list", "--json"]:
    counter_path = Path(os.environ["FAKE_FLYCTL_COUNTER"])
    count = int(counter_path.read_text(encoding="utf-8")) if counter_path.exists() else 0
    snapshots = json.loads(
        Path(os.environ["FAKE_FLYCTL_SNAPSHOTS"]).read_text(encoding="utf-8")
    )
    selected = snapshots[min(count, len(snapshots) - 1)]
    counter_path.write_text(str(count + 1), encoding="utf-8")
    print(json.dumps(selected))
    raise SystemExit(0)

if args == ["-c", "fly.toml", "status", "--json"]:
    print('{"status": "deployed"}')

raise SystemExit(0)
""",
        encoding="utf-8",
    )
    executable.chmod(0o755)
    return calls_path, counter_path


def _run_deploy_step(
    tmp_path: Path,
    name: str,
    snapshots: list[list[dict[str, object]]],
    *,
    extra_env: dict[str, str] | None = None,
) -> tuple[subprocess.CompletedProcess[str], list[list[str]]]:
    """Run a workflow shell step against deterministic local Flyctl responses."""
    calls_path, counter_path = _install_fake_flyctl(tmp_path, snapshots)
    step = _deploy_step(name)
    env = os.environ.copy()
    env.update({key: str(value) for key, value in step.get("env", {}).items()})
    env.update(
        {
            "PATH": f"{tmp_path}:{Path(sys.executable).parent}:{env['PATH']}",
            "FAKE_FLYCTL_CALLS": str(calls_path),
            "FAKE_FLYCTL_COUNTER": str(counter_path),
            "FAKE_FLYCTL_SNAPSHOTS": str(tmp_path / "machine-snapshots.json"),
            "GITHUB_OUTPUT": str(tmp_path / "github-output"),
        }
    )
    if extra_env:
        env.update(extra_env)

    result = subprocess.run(
        ["bash", "-c", f"set -euo pipefail\n{step['run']}"],
        cwd=BACKEND_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    calls = (
        [json.loads(line) for line in calls_path.read_text().splitlines()]
        if calls_path.exists()
        else []
    )
    return result, calls


def test_reconciliation_lists_once_and_preserves_existing_stopped_machine(
    tmp_path: Path,
) -> None:
    """One topology snapshot should preserve every existing Machine state."""
    result, calls = _run_deploy_step(
        tmp_path,
        "Reconcile Fly Machine topology",
        [_healthy_topology()],
    )

    assert result.returncode == 0, result.stderr
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]


def test_reconciliation_exports_the_validated_notification_identity(
    tmp_path: Path,
) -> None:
    """Recovery should consume the exact notification ID validated at reconciliation."""
    result, calls = _run_deploy_step(
        tmp_path,
        "Reconcile Fly Machine topology",
        [_healthy_topology()],
    )

    assert result.returncode == 0, result.stderr
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    output_path = tmp_path / "github-output"
    assert output_path.exists(), "Reconciliation did not write its step output"
    assert output_path.read_text(encoding="utf-8") == (
        f"notification_machine_id={NOTIFICATION_MACHINE_ID}\n"
    )


def test_notification_recovery_depends_on_reconciled_step_identity() -> None:
    """GitHub Actions should pass the reconciled ID into notification recovery."""
    reconcile_step = _deploy_step("Reconcile Fly Machine topology")
    recovery_step = _deploy_step("Start and verify notification control Machine")

    assert reconcile_step["id"] == "topology"
    assert recovery_step["env"]["RECONCILED_NOTIFICATION_MACHINE_ID"] == (
        "${{ steps.topology.outputs.notification_machine_id }}"
    )


def test_reconciliation_scales_only_missing_process_groups(tmp_path: Path) -> None:
    """Missing groups should be created without scaling or starting existing groups."""
    topology = _healthy_topology()
    topology = [
        machine
        for machine in topology
        if machine["id"] not in {NOTIFICATION_MACHINE_ID, INGESTION_MACHINE_ID}
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Reconcile Fly Machine topology",
        [topology],
    )

    assert result.returncode == 0, result.stderr
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        [
            "-c",
            "fly.toml",
            "scale",
            "count",
            "1",
            "--yes",
            "--process-group",
            "notification",
            "--region",
            "lhr",
        ],
        [
            "-c",
            "fly.toml",
            "scale",
            "count",
            "1",
            "--yes",
            "--process-group",
            "ingestion",
            "--region",
            "lhr",
        ],
    ]


def test_reconciliation_fails_on_duplicate_group_without_mutation(
    tmp_path: Path,
) -> None:
    """Duplicate groups must fail instead of choosing or scaling a Machine."""
    topology = [
        *_healthy_topology(),
        _machine(DUPLICATE_MACHINE_ID, "website", "stopped"),
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Reconcile Fly Machine topology",
        [topology],
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert "duplicate website Machines" in result.stderr
    assert '"website"' in result.stderr
    assert '"count": 2' in result.stderr
    assert WEBSITE_MACHINE_ID not in result.stderr
    assert DUPLICATE_MACHINE_ID not in result.stderr


@pytest.mark.parametrize(
    "invalid_machine",
    [
        _machine(DUPLICATE_MACHINE_ID, "unknown", "started"),
        {
            "id": DUPLICATE_MACHINE_ID,
            "state": {"token": "STATE_SECRET_SENTINEL"},
            "region": "lhr",
            "config": {"metadata": {"fly_process_group": "website"}},
        },
        {
            "id": DUPLICATE_MACHINE_ID,
            "state": "started",
            "region": "lhr",
            "config": ["malformed"],
        },
    ],
)
def test_reconciliation_fails_closed_on_unknown_or_malformed_machine(
    tmp_path: Path,
    invalid_machine: dict[str, object],
) -> None:
    """Unrecognised or malformed Machines should block every topology mutation."""
    invalid_machine["authorization"] = "TOPOLOGY_SECRET_SENTINEL"
    topology = [*_healthy_topology(), invalid_machine]

    result, calls = _run_deploy_step(
        tmp_path,
        "Reconcile Fly Machine topology",
        [topology],
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert "Fly Machine topology is invalid" in result.stderr
    assert "TOPOLOGY_SECRET_SENTINEL" not in result.stderr
    assert "STATE_SECRET_SENTINEL" not in result.stderr


@pytest.mark.parametrize(
    ("field", "invalid_value", "sentinel"),
    [
        ("id", "TOKEN_ID_SECRET_SENTINEL", "TOKEN_ID_SECRET_SENTINEL"),
        ("id", "abcd;ID_SHELL_SENTINEL", "ID_SHELL_SENTINEL"),
        ("id", "abcd\nID_NEWLINE_SENTINEL", "ID_NEWLINE_SENTINEL"),
        ("region", "TOKEN_REGION_SECRET_SENTINEL", "TOKEN_REGION_SECRET_SENTINEL"),
        ("region", "lhr;REGION_SHELL_SENTINEL", "REGION_SHELL_SENTINEL"),
        ("region", "lh\nREGION_NEWLINE_SENTINEL", "REGION_NEWLINE_SENTINEL"),
        ("region", "london", "london"),
        (
            "region",
            {"token": "NESTED_REGION_SECRET_SENTINEL"},
            "NESTED_REGION_SECRET_SENTINEL",
        ),
    ],
)
def test_reconciliation_rejects_untrusted_machine_identifiers_before_scaling(
    tmp_path: Path,
    field: str,
    invalid_value: object,
    sentinel: str,
) -> None:
    """Malformed Fly IDs or regions must fail before any missing-group scale."""
    topology = [
        machine
        for machine in _healthy_topology()
        if machine["id"] != INGESTION_MACHINE_ID
    ]
    website = next(
        machine for machine in topology if machine["id"] == WEBSITE_MACHINE_ID
    )
    website[field] = invalid_value

    result, calls = _run_deploy_step(
        tmp_path,
        "Reconcile Fly Machine topology",
        [topology],
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert sentinel not in result.stdout
    assert sentinel not in result.stderr


def test_notification_recovery_starts_existing_machine_and_verifies_started(
    tmp_path: Path,
) -> None:
    """A stopped control Machine should be started by ID and observed as started."""
    result, calls = _run_deploy_step(
        tmp_path,
        "Start and verify notification control Machine",
        [
            _healthy_topology(notification_state="stopped"),
            _healthy_topology(notification_state="started"),
        ],
        extra_env={
            "RECONCILED_NOTIFICATION_MACHINE_ID": NOTIFICATION_MACHINE_ID,
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode == 0, result.stderr
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "start", NOTIFICATION_MACHINE_ID],
        ["-c", "fly.toml", "machine", "list", "--json"],
    ]


@pytest.mark.parametrize("duplicate_group", ["app", "website", "ingestion"])
def test_notification_recovery_rejects_non_notification_duplicates_before_start(
    tmp_path: Path,
    duplicate_group: str,
) -> None:
    """Every recovery relist must validate all four groups before mutation."""
    first_snapshot = [
        *_healthy_topology(notification_state="stopped"),
        _machine(DUPLICATE_MACHINE_ID, duplicate_group, "stopped"),
    ]
    second_snapshot = [
        *_healthy_topology(notification_state="started"),
        _machine(DUPLICATE_MACHINE_ID, duplicate_group, "stopped"),
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Start and verify notification control Machine",
        [first_snapshot, second_snapshot],
        extra_env={
            "RECONCILED_NOTIFICATION_MACHINE_ID": NOTIFICATION_MACHINE_ID,
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert f"duplicate {duplicate_group} Machines" in result.stderr
    assert DUPLICATE_MACHINE_ID not in result.stderr


@pytest.mark.parametrize(
    "invalid_machine",
    [
        _machine(DUPLICATE_MACHINE_ID, "unknown", "started"),
        {
            "id": DUPLICATE_MACHINE_ID,
            "state": "started",
            "region": "lhr",
            "config": ["malformed"],
        },
        _machine(
            DUPLICATE_MACHINE_ID,
            "website",
            "started",
            region="TOKEN_RECOVERY_REGION_SENTINEL",
        ),
    ],
)
def test_notification_recovery_rejects_unknown_or_malformed_rows_before_start(
    tmp_path: Path,
    invalid_machine: dict[str, object],
) -> None:
    """Recovery must fail closed on every unrecognised or malformed Machine row."""
    topology = [*_healthy_topology(notification_state="stopped"), invalid_machine]

    result, calls = _run_deploy_step(
        tmp_path,
        "Start and verify notification control Machine",
        [topology, _healthy_topology(notification_state="started")],
        extra_env={
            "RECONCILED_NOTIFICATION_MACHINE_ID": NOTIFICATION_MACHINE_ID,
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert "TOKEN_RECOVERY_REGION_SENTINEL" not in result.stdout
    assert "TOKEN_RECOVERY_REGION_SENTINEL" not in result.stderr


def test_notification_recovery_revalidates_full_topology_after_start(
    tmp_path: Path,
) -> None:
    """A duplicate introduced after start must fail before accepting notification."""
    duplicate_snapshot = [
        *_healthy_topology(notification_state="started"),
        _machine(DUPLICATE_MACHINE_ID, "website", "stopped"),
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Start and verify notification control Machine",
        [
            _healthy_topology(notification_state="stopped"),
            duplicate_snapshot,
        ],
        extra_env={
            "RECONCILED_NOTIFICATION_MACHINE_ID": NOTIFICATION_MACHINE_ID,
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "start", NOTIFICATION_MACHINE_ID],
        ["-c", "fly.toml", "machine", "list", "--json"],
    ]
    assert "duplicate website Machines" in result.stderr


def test_notification_recovery_fails_when_notification_identity_changes(
    tmp_path: Path,
) -> None:
    """Recovery must never start a second notification ID after topology churn."""
    result, calls = _run_deploy_step(
        tmp_path,
        "Start and verify notification control Machine",
        [
            _healthy_topology(notification_state="stopped"),
            _healthy_topology(
                notification_state="stopped",
                notification_id=ALTERNATE_NOTIFICATION_MACHINE_ID,
            ),
            _healthy_topology(
                notification_state="started",
                notification_id=ALTERNATE_NOTIFICATION_MACHINE_ID,
            ),
        ],
        extra_env={
            "RECONCILED_NOTIFICATION_MACHINE_ID": NOTIFICATION_MACHINE_ID,
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "start", NOTIFICATION_MACHINE_ID],
        ["-c", "fly.toml", "machine", "list", "--json"],
    ]
    assert ALTERNATE_NOTIFICATION_MACHINE_ID not in result.stdout
    assert ALTERNATE_NOTIFICATION_MACHINE_ID not in result.stderr


def test_notification_recovery_fails_on_ambiguous_control_topology(
    tmp_path: Path,
) -> None:
    """Notification recovery must never select arbitrarily from duplicates."""
    topology = [
        *_healthy_topology(notification_state="stopped"),
        _machine(DUPLICATE_MACHINE_ID, "notification", "stopped"),
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Start and verify notification control Machine",
        [topology],
        extra_env={
            "RECONCILED_NOTIFICATION_MACHINE_ID": NOTIFICATION_MACHINE_ID,
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert "duplicate notification Machines" in result.stderr


@pytest.mark.parametrize(
    "state",
    ["started", "starting", "stopping", "stopped", "suspended"],
)
def test_lifecycle_verification_accepts_every_documented_demand_state(
    tmp_path: Path,
    state: str,
) -> None:
    """API and demand workers may occupy any documented healthy lifecycle state."""
    result, calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [
            _healthy_topology(
                app_state=state,
                website_state=state,
                ingestion_state=state,
            )
        ],
        extra_env={"DEMAND_WORKER_SETTLE_SECONDS": "0"},
    )

    assert result.returncode == 0, result.stderr
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]


def test_lifecycle_verification_waits_for_topology_then_for_workers_to_stop(
    tmp_path: Path,
) -> None:
    """Missing-only discovery and active work should both retry with stable IDs."""
    missing_website = [
        machine
        for machine in _healthy_topology()
        if machine["id"] != WEBSITE_MACHINE_ID
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [
            missing_website,
            _healthy_topology(website_state="started", ingestion_state="stopped"),
            _healthy_topology(website_state="stopped", ingestion_state="suspended"),
        ],
        extra_env={
            "DEMAND_WORKER_SETTLE_SECONDS": "1",
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode == 0, result.stderr
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "list", "--json"],
    ]


def test_lifecycle_verification_fails_when_missing_topology_never_converges(
    tmp_path: Path,
) -> None:
    """A missing group should fail safely when the existing deadline expires."""
    missing_website = [
        machine
        for machine in _healthy_topology()
        if machine["id"] != WEBSITE_MACHINE_ID
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [missing_website],
        extra_env={
            "DEMAND_WORKER_SETTLE_SECONDS": "0",
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert "topology did not converge before the lifecycle deadline" in result.stderr


def test_lifecycle_verification_rejects_duplicate_during_topology_wait(
    tmp_path: Path,
) -> None:
    """A duplicate discovered after a missing-only snapshot should fail immediately."""
    missing_website = [
        machine
        for machine in _healthy_topology()
        if machine["id"] != WEBSITE_MACHINE_ID
    ]
    duplicate_website = [
        *_healthy_topology(),
        _machine(DUPLICATE_MACHINE_ID, "website", "stopped"),
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [missing_website, duplicate_website],
        extra_env={
            "DEMAND_WORKER_SETTLE_SECONDS": "1",
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "list", "--json"],
    ]
    assert "duplicate website Machines" in result.stderr
    assert DUPLICATE_MACHINE_ID not in result.stderr


@pytest.mark.parametrize(
    "invalid_machine",
    [
        _machine(DUPLICATE_MACHINE_ID, "unknown", "started"),
        _machine(DUPLICATE_MACHINE_ID, "website", "failed"),
        _machine(
            DUPLICATE_MACHINE_ID,
            "website",
            "started",
            region="LIFECYCLE_REGION_SECRET_SENTINEL",
        ),
        {
            "id": DUPLICATE_MACHINE_ID,
            "state": "started",
            "region": "lhr",
            "config": ["malformed"],
        },
    ],
)
def test_lifecycle_verification_rejects_invalid_rows_during_topology_wait(
    tmp_path: Path,
    invalid_machine: dict[str, object],
) -> None:
    """Unknown, malformed, or invalid-state rows must not become retryable missing."""
    missing_website = [
        machine
        for machine in _healthy_topology()
        if machine["id"] != WEBSITE_MACHINE_ID
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [missing_website, [*_healthy_topology(), invalid_machine]],
        extra_env={
            "DEMAND_WORKER_SETTLE_SECONDS": "1",
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "list", "--json"],
    ]
    assert "LIFECYCLE_REGION_SECRET_SENTINEL" not in result.stdout
    assert "LIFECYCLE_REGION_SECRET_SENTINEL" not in result.stderr


def test_lifecycle_verification_rejects_machine_identity_churn(
    tmp_path: Path,
) -> None:
    """A later exact snapshot must retain every initially validated Machine ID."""
    result, calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [
            _healthy_topology(website_state="started"),
            _healthy_topology(
                website_state="stopped",
                notification_id=ALTERNATE_NOTIFICATION_MACHINE_ID,
            ),
        ],
        extra_env={
            "DEMAND_WORKER_SETTLE_SECONDS": "1",
            "FLY_MACHINE_POLL_SECONDS": "0",
        },
    )

    assert result.returncode != 0
    assert calls == [
        ["-c", "fly.toml", "machine", "list", "--json"],
        ["-c", "fly.toml", "machine", "list", "--json"],
    ]
    assert "Machine identity changed during lifecycle verification" in result.stderr
    assert ALTERNATE_NOTIFICATION_MACHINE_ID not in result.stderr


def test_lifecycle_verification_requires_exactly_one_machine_per_group(
    tmp_path: Path,
) -> None:
    """Final verification should reject duplicate demand-worker topology."""
    topology = [
        *_healthy_topology(),
        _machine(DUPLICATE_MACHINE_ID, "ingestion", "stopped"),
    ]

    result, calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [topology],
        extra_env={"DEMAND_WORKER_SETTLE_SECONDS": "0"},
    )

    assert result.returncode != 0
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert "duplicate ingestion Machines" in result.stderr
    assert DUPLICATE_MACHINE_ID not in result.stderr


def test_lifecycle_verification_logs_and_continues_for_active_demand_work(
    tmp_path: Path,
) -> None:
    """A worker that remains active through the settle window should not fail deploy."""
    step = _deploy_step("Verify demand-aware Fly Machine lifecycle")
    result, _calls = _run_deploy_step(
        tmp_path,
        "Verify demand-aware Fly Machine lifecycle",
        [_healthy_topology(website_state="started", ingestion_state="starting")],
        extra_env={"DEMAND_WORKER_SETTLE_SECONDS": "0"},
    )

    assert step["env"]["DEMAND_WORKER_SETTLE_SECONDS"] == "90"
    assert result.returncode == 0, result.stderr
    assert "queued work may still be active" in result.stdout
    assert "website=started" in result.stdout
    assert "ingestion=starting" in result.stdout


def test_scoped_failure_diagnostics_project_only_credential_safe_fields(
    tmp_path: Path,
) -> None:
    """Failure diagnostics must not print Machine config, env, or credentials."""
    topology = _healthy_topology()
    topology[0]["id"] = "TOKEN_DIAGNOSTIC_ID_SENTINEL"
    topology[0]["region"] = "lhr;DIAGNOSTIC_REGION_SHELL_SENTINEL"
    topology[0]["authorization"] = "DIAGNOSTIC_AUTH_SECRET"
    topology[0]["config"] = {
        "metadata": {
            "fly_process_group": "app",
            "token": "DIAGNOSTIC_METADATA_SECRET",
        },
        "env": {
            "FLY_PROCESS_GROUP": "app",
            "FLY_WORKER_CONTROL_TOKEN": "DIAGNOSTIC_ENV_SECRET",
        },
    }
    topology[1]["id"] = "abcd;DIAGNOSTIC_ID_SHELL_SENTINEL"
    topology[1]["region"] = "lh\nDIAGNOSTIC_REGION_NEWLINE_SENTINEL"
    topology[2]["id"] = "abcd\nDIAGNOSTIC_ID_NEWLINE_SENTINEL"
    topology[2]["region"] = "london"
    topology[3]["region"] = "token-region-secret"

    result, calls = _run_deploy_step(
        tmp_path,
        "Collect scoped Fly diagnostics on failure",
        [topology],
    )

    assert result.returncode == 0, result.stderr
    assert calls == [["-c", "fly.toml", "machine", "list", "--json"]]
    assert '"app"' in result.stdout
    assert '"count": 1' in result.stdout
    assert INGESTION_MACHINE_ID not in result.stdout
    assert "lhr" not in result.stdout
    for sentinel in (
        "TOKEN_DIAGNOSTIC_ID_SENTINEL",
        "DIAGNOSTIC_ID_SHELL_SENTINEL",
        "DIAGNOSTIC_ID_NEWLINE_SENTINEL",
        "DIAGNOSTIC_REGION_SHELL_SENTINEL",
        "DIAGNOSTIC_REGION_NEWLINE_SENTINEL",
        "london",
        "token-region-secret",
        "DIAGNOSTIC_AUTH_SECRET",
        "DIAGNOSTIC_METADATA_SECRET",
        "DIAGNOSTIC_ENV_SECRET",
    ):
        assert sentinel not in result.stdout
        assert sentinel not in result.stderr
    assert (
        _deploy_step("Collect scoped Fly diagnostics on failure")["if"] == "failure()"
    )


def test_fly_deploy_workflow_restricts_manual_prod_deploys_to_main() -> None:
    """Manual dispatch should not deploy the production app from non-main branches."""
    deploy_job = _workflow()["jobs"]["deploy"]

    deploy_condition = deploy_job["if"]
    assert "github.event_name == 'push'" in deploy_condition
    assert "github.event_name == 'workflow_dispatch'" in deploy_condition
    assert "github.ref == 'refs/heads/main'" in deploy_condition


def test_fly_deploy_workflow_authenticates_with_flyctl_before_push() -> None:
    """Fly deploy should refresh registry auth right before pushing the image."""
    deploy_steps = _workflow()["jobs"]["deploy"]["steps"]

    install_index = next(
        index
        for index, step in enumerate(deploy_steps)
        if step.get("name") == "Install Flyctl"
    )
    auth_index = next(
        index
        for index, step in enumerate(deploy_steps)
        if step.get("name") == "Authenticate Docker to Fly registry"
    )
    push_index = next(
        index
        for index, step in enumerate(deploy_steps)
        if step.get("name") == "Push image to Fly registry"
    )

    assert install_index < auth_index < push_index
    assert "flyctl auth docker" in deploy_steps[auth_index]["run"]
    assert "${{ secrets.FLY_API_TOKEN }}" in str(deploy_steps[auth_index]["env"])


def test_fly_deploy_workflow_retries_registry_authentication() -> None:
    """Fly deploy should retry transient registry auth failures before giving up."""
    run_script = _deploy_step("Authenticate Docker to Fly registry")["run"]

    assert "for attempt in 1 2 3" in run_script
    assert "flyctl auth docker" in run_script
    assert 'if [ "$attempt" -eq 3 ]' in run_script
    assert "sleep $((attempt * 5))" in run_script


def test_fly_deploy_workflow_builds_before_registry_push() -> None:
    """Fly deploy should avoid authenticating until after the build completes."""
    deploy_steps = _workflow()["jobs"]["deploy"]["steps"]
    build_step = next(
        step for step in deploy_steps if step.get("name") == "Build image"
    )
    push_step = _deploy_step("Push image to Fly registry")

    assert build_step["uses"] == "docker/build-push-action@v7"
    assert build_step["with"]["push"] == "false"
    assert build_step["with"]["load"] == "true"
    assert build_step["with"]["tags"] == "${{ steps.image.outputs.ref }}"
    assert push_step["run"] == 'docker push "${{ steps.image.outputs.ref }}"'


def test_fly_deploy_workflow_opts_into_node24_for_javascript_actions() -> None:
    """Fly deploy should opt into Node 24 before GitHub flips the default."""
    assert _workflow()["env"]["FORCE_JAVASCRIPT_ACTIONS_TO_NODE24"] == "true"
