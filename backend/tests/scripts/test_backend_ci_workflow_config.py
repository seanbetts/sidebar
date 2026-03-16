"""Regression tests for the committed backend CI workflow."""

from __future__ import annotations

from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
BACKEND_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "backend-ci.yml"


def _workflow() -> dict[str, object]:
    """Return the committed backend CI workflow payload."""
    return yaml.load(BACKEND_WORKFLOW_PATH.read_text(), Loader=yaml.BaseLoader)


def test_backend_workflow_triggers_on_backend_and_script_inputs() -> None:
    """Backend CI should rerun when backend-owned script inputs change on dev."""
    workflow = _workflow()

    assert workflow["name"] == "Backend CI"
    assert set(workflow["on"]["push"]["branches"]) == {"dev"}
    assert set(workflow["on"]["push"]["paths"]) == {
        "backend/**",
        "scripts/validate_ios_test_taxonomy.py",
        "scripts/ios_test_taxonomy.json",
        ".github/workflows/backend-ci.yml",
    }


def test_backend_workflow_uses_auth_and_health_safe_test_env() -> None:
    """Backend CI should not force auth-dev mode and should satisfy health config."""
    workflow = _workflow()
    env = workflow["jobs"]["test"]["env"]

    assert env["TESTING"] == "1"
    assert env["AUTH_DEV_MODE"] == "false"
    assert env["SUPABASE_URL"] == "https://example.supabase.co"
