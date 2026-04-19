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
        "flyctl -c fly.toml scale count 1 --yes --process-group ingestion --region lhr"
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
    assert "def machine_process_group" in run_script
    assert 'metadata.get("fly_process_group")' in run_script
    assert 'env.get("FLY_PROCESS_GROUP")' in run_script
    assert 'machine_process_group(machine) == "ingestion"' in run_script
    assert 'machine.get("state") == "started"' in run_script


def test_fly_deploy_workflow_scales_website_process_group() -> None:
    """Fly deploy should explicitly keep one website worker machine running."""
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

    matching_steps = [
        step
        for step in deploy_steps
        if step.get("name") == "Ensure website worker machine is running"
    ]

    assert matching_steps, "Missing website worker scale step"
    assert (
        "flyctl -c fly.toml scale count 1 --yes --process-group website --region lhr"
        in matching_steps[0]["run"]
    )


def test_fly_deploy_workflow_verifies_website_machine_is_started() -> None:
    """Fly deploy should fail fast if the website worker machine is not started."""
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

    matching_steps = [
        step
        for step in deploy_steps
        if step.get("name") == "Verify website worker machine state"
    ]

    assert matching_steps, "Missing website worker verification step"
    run_script = matching_steps[0]["run"]
    assert 'machine_process_group(machine) == "website"' in run_script
    assert 'machine.get("state") == "started"' in run_script


def test_fly_deploy_workflow_authenticates_with_flyctl_before_push() -> None:
    """Fly deploy should refresh registry auth right before pushing the image."""
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

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
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

    auth_step = next(
        step
        for step in deploy_steps
        if step.get("name") == "Authenticate Docker to Fly registry"
    )
    run_script = auth_step["run"]

    assert "for attempt in 1 2 3" in run_script
    assert "flyctl auth docker" in run_script
    assert 'if [ "$attempt" -eq 3 ]' in run_script
    assert "sleep $((attempt * 5))" in run_script


def test_fly_deploy_workflow_builds_before_registry_push() -> None:
    """Fly deploy should avoid authenticating to the registry until after build completes."""
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

    build_step = next(
        step for step in deploy_steps if step.get("name") == "Build image"
    )
    push_step = next(
        step for step in deploy_steps if step.get("name") == "Push image to Fly registry"
    )

    assert build_step["uses"] == "docker/build-push-action@v6"
    assert build_step["with"]["push"] == "false"
    assert build_step["with"]["load"] == "true"
    assert build_step["with"]["tags"] == "${{ steps.image.outputs.ref }}"
    assert push_step["run"] == 'docker push "${{ steps.image.outputs.ref }}"'


def test_fly_deploy_workflow_opts_into_node24_for_javascript_actions() -> None:
    """Fly deploy should opt into Node 24 before GitHub flips the default."""
    workflow = _workflow()

    assert workflow["env"]["FORCE_JAVASCRIPT_ACTIONS_TO_NODE24"] == "true"


def test_fly_deploy_workflow_collects_fly_diagnostics_after_failed_deploy() -> None:
    """Fly deploy should print machine state and logs when the deploy step fails."""
    workflow = _workflow()
    deploy_steps = workflow["jobs"]["deploy"]["steps"]

    diagnostics_step = next(
        step
        for step in deploy_steps
        if step.get("name") == "Collect Fly diagnostics on deploy failure"
    )

    assert diagnostics_step["if"] == "failure()"
    run_script = diagnostics_step["run"]
    assert 'flyctl -c fly.toml status --json || true' in run_script
    assert 'flyctl -c fly.toml machine list --json || true' in run_script
    assert 'flyctl -c fly.toml logs --json --no-tail --region lhr || true' in run_script
