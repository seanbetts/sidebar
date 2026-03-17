"""Regression tests for the committed Fly deploy workflow."""

from __future__ import annotations

from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
FLY_DEPLOY_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "fly-deploy.yml"


def _workflow() -> dict[str, object]:
    """Return the committed Fly deploy workflow payload."""
    return yaml.load(FLY_DEPLOY_WORKFLOW_PATH.read_text(), Loader=yaml.BaseLoader)


def test_fly_deploy_workflow_scales_ingestion_process_group() -> None:
    """Fly deploy should explicitly keep one ingestion worker machine running."""
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

    matching_steps = [
        step
        for step in deploy_steps
        if step.get("name") == "Ensure ingestion worker machine is running"
    ]

    assert matching_steps, "Missing ingestion worker scale step"
    run_script = matching_steps[0]["run"]
    assert (
        "flyctl -c fly.toml scale count 1 --process-group ingestion --region lhr"
        in run_script
    )


def test_fly_deploy_workflow_verifies_ingestion_machine_is_started() -> None:
    """Fly deploy should fail fast if the ingestion worker machine is not started."""
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

    matching_steps = [
        step
        for step in deploy_steps
        if step.get("name") == "Verify ingestion worker machine state"
    ]

    assert matching_steps, "Missing ingestion worker verification step"
    run_script = matching_steps[0]["run"]
    assert '"machine", "list", "--json"' in run_script
    assert 'machine.get("process_group") == "ingestion"' in run_script
    assert 'machine.get("state") == "started"' in run_script
