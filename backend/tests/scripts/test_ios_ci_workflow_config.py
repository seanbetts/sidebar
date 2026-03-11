"""Regression tests for the committed iOS CI lane configuration."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ios-ci.yml"
BASELINE_ARTIFACT_PATH = (
    REPO_ROOT / "docs" / "plans" / "artifacts" / "apple-testing-baseline-2026-03-11.md"
)
XCODE_PROJECT_PATH = REPO_ROOT / "ios" / "sideBar" / "sideBar.xcodeproj"
APPLE_FAST_PLAN_PATH = (
    XCODE_PROJECT_PATH / "xcshareddata" / "xctestplans" / "AppleFast.xctestplan"
)

MODULE_PATH = REPO_ROOT / "scripts" / "validate_ios_test_lane.py"
MODULE_SPEC = importlib.util.spec_from_file_location("validate_ios_test_lane", MODULE_PATH)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
VALIDATE_LANE_MODULE = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(VALIDATE_LANE_MODULE)

effective_test_targets = VALIDATE_LANE_MODULE.effective_test_targets
parse_csv_specs = VALIDATE_LANE_MODULE.parse_csv_specs
read_scheme_test_targets = VALIDATE_LANE_MODULE.read_scheme_test_targets
validate_lane = VALIDATE_LANE_MODULE.validate_lane


def _load_ios_ci_workflow() -> dict[str, object]:
    """Return the committed iOS CI workflow payload."""
    return yaml.load(WORKFLOW_PATH.read_text(), Loader=yaml.BaseLoader)


def _load_ios_ci_matrix() -> list[dict[str, str]]:
    """Return the configured iOS test matrix entries from the workflow."""
    workflow = _load_ios_ci_workflow()
    return workflow["jobs"]["ios_test_matrix"]["strategy"]["matrix"]["include"]


def _matrix_entry(entry_id: str) -> dict[str, str]:
    """Return the workflow matrix row for a given lane id."""
    for entry in _load_ios_ci_matrix():
        if entry["id"] == entry_id:
            return entry
    raise AssertionError(f"Missing iOS CI matrix entry: {entry_id}")


def _ios_test_run_step() -> dict[str, object]:
    """Return the shared test-execution step from the workflow."""
    workflow = _load_ios_ci_workflow()
    for step in workflow["jobs"]["ios_test_matrix"]["steps"]:
        if step.get("name", "").startswith("Run tests"):
            return step
    raise AssertionError("Missing iOS test execution step")


def _resolve_specs_step() -> dict[str, object]:
    """Return the taxonomy spec-resolution step from the workflow."""
    workflow = _load_ios_ci_workflow()
    for step in workflow["jobs"]["ios_test_matrix"]["steps"]:
        if step.get("name", "").startswith("Resolve taxonomy test specs"):
            return step
    raise AssertionError("Missing taxonomy test spec resolution step")


def _test_target_names_from_plan(path: Path) -> set[str]:
    """Return test target names from an Xcode `.xctestplan` file."""
    payload = json.loads(path.read_text())
    return {
        target["target"]["name"]
        for target in payload.get("testTargets", [])
        if isinstance(target, dict)
        and isinstance(target.get("target"), dict)
        and isinstance(target["target"].get("name"), str)
    }


def test_logic_lane_configuration_validates_against_committed_scheme() -> None:
    """The logic lane should resolve to deterministic macOS-compatible tests."""
    lane = _matrix_entry("logic")
    scheme_targets = read_scheme_test_targets(XCODE_PROJECT_PATH, lane["scheme"])
    effective_targets = effective_test_targets(
        scheme_targets,
        parse_csv_specs(lane.get("only_testing", "")),
        parse_csv_specs(lane.get("skip_testing", "")),
    )

    assert validate_lane(
        lane["destination"],
        scheme_targets,
        effective_targets,
        {"sideBarTests"},
    ) == []
    assert effective_targets == ["sideBarTests"]


def test_apple_testing_baseline_artifact_exists() -> None:
    """The Apple testing reset should keep a checked-in baseline artifact."""
    assert BASELINE_ARTIFACT_PATH.exists()


def test_surface_lane_configuration_uses_sidebar_scheme_and_surface_plan() -> None:
    """The surface lane should run broader app-surface coverage on iOS."""
    lane = _matrix_entry("surface")

    assert lane["scheme"] == "sideBar"
    assert lane["test_plan"] == "AppleStateful"
    assert lane["run_on_dev"] == "NO"
    assert lane["run_on_main"] == "YES"


def test_ui_lane_configuration_uses_the_split_ui_scheme() -> None:
    """The UI smoke lane should use the split UI scheme on main."""
    lane = _matrix_entry("ui")

    assert lane["scheme"] == "sideBarUI"
    assert lane["test_plan"] == "AppleUI"
    assert lane["run_on_dev"] == "NO"
    assert lane["run_on_main"] == "YES"


def test_extensions_lane_configuration_uses_the_split_extensions_scheme() -> None:
    """The extension lane should protect extension surfaces on main."""
    lane = _matrix_entry("extensions")

    assert lane["scheme"] == "sideBarExtensions"
    assert lane["test_plan"] == "AppleExtensions"
    assert lane["run_on_dev"] == "NO"
    assert lane["run_on_main"] == "YES"


def test_apple_fast_plan_excludes_share_extension_tests() -> None:
    """The fast plan should stay limited to deterministic app tests."""
    assert _test_target_names_from_plan(APPLE_FAST_PLAN_PATH) == {"sideBarTests"}


def test_ios_ci_does_not_run_for_pull_requests() -> None:
    """The simplified iOS workflow should trigger on push and manual runs only."""
    workflow = _load_ios_ci_workflow()

    assert "pull_request" not in workflow["on"]


def test_ios_ci_pushes_run_on_dev_and_main() -> None:
    """Branch-specific Apple routing should exist for both development branches."""
    workflow = _load_ios_ci_workflow()

    assert set(workflow["on"]["push"]["branches"]) == {"dev", "main"}


def test_ios_ci_push_paths_include_swiftlint_config() -> None:
    """SwiftLint config changes should trigger the workflow that consumes them."""
    workflow = _load_ios_ci_workflow()
    push_paths = workflow["on"]["push"]["paths"]

    assert ".swiftlint.yml" in push_paths
    assert "scripts/ios_test_taxonomy.json" in push_paths
    assert "scripts/validate_ios_test_taxonomy.py" in push_paths
    assert "scripts/resolve_ios_test_specs.py" in push_paths


def test_ios_ci_jobs_define_timeouts() -> None:
    """Self-hosted iOS jobs should not run without a hard timeout."""
    jobs = _load_ios_ci_workflow()["jobs"]

    assert jobs["ios_quality"]["timeout-minutes"] == "30"
    assert jobs["ios_test_matrix"]["timeout-minutes"] == "90"


def test_ios_ci_branch_routing_marks_dev_logic_only_and_main_broader() -> None:
    """Matrix rows should encode the intended branch-specific Apple coverage."""
    dev_push_lanes = {
        entry["id"] for entry in _load_ios_ci_matrix() if entry.get("run_on_dev") == "YES"
    }
    main_push_lanes = {
        entry["id"]
        for entry in _load_ios_ci_matrix()
        if entry.get("run_on_main") == "YES"
    }

    assert dev_push_lanes == {"logic"}
    assert main_push_lanes == {"logic", "surface", "ui", "extensions"}


def test_ios_ci_dispatch_lane_options_match_matrix_entries() -> None:
    """Manual dispatch options should map cleanly onto the configured lanes."""
    workflow = _load_ios_ci_workflow()
    options = workflow["on"]["workflow_dispatch"]["inputs"]["lane"]["options"]
    matrix_ids = {entry["id"] for entry in _load_ios_ci_matrix()}

    assert set(options) == {"all"} | matrix_ids


def test_ios_ci_ui_lane_receives_explicit_ui_test_secrets() -> None:
    """The manual UI lane should receive dedicated auth secrets and shared config."""
    run_step = _ios_test_run_step()
    env = run_step["env"]

    assert env["IOS_ONLY_TESTING"] == "${{ env.IOS_ONLY_TESTING }}"
    assert env["SIDEBAR_UI_TEST_EMAIL"] == "${{ secrets.SIDEBAR_UI_TEST_EMAIL }}"
    assert env["SIDEBAR_UI_TEST_PASSWORD"] == "${{ secrets.SIDEBAR_UI_TEST_PASSWORD }}"
    assert env["API_BASE_URL"] == "${{ secrets.API_BASE_URL }}"
    assert env["SUPABASE_URL"] == "${{ secrets.SUPABASE_URL }}"
    assert env["SUPABASE_ANON_KEY"] == "${{ secrets.SUPABASE_ANON_KEY }}"


def test_ios_ci_resolves_only_testing_specs_from_taxonomy() -> None:
    """Workflow should derive Apple test specs from the committed taxonomy."""
    resolve_step = _resolve_specs_step()
    step_script = resolve_step["run"]
    matrix = {entry["id"]: entry for entry in _load_ios_ci_matrix()}

    assert "python3 scripts/resolve_ios_test_specs.py" in step_script
    assert "IOS_ONLY_TESTING=" in step_script
    assert "dev_logic" in step_script
    assert matrix["logic"]["spec_selection_main"] == "main_logic"
    assert matrix["surface"]["spec_selection_main"] == "main_surface"
    assert matrix["extensions"]["spec_selection_main"] == "main_extensions"
    assert matrix["ui"]["spec_selection_main"] == "ui_smoke"


def test_ios_ci_uses_node24_compatible_actions() -> None:
    """The workflow should use action versions that avoid Node 20 deprecation."""
    jobs = _load_ios_ci_workflow()["jobs"]
    all_steps = jobs["ios_quality"]["steps"] + jobs["ios_test_matrix"]["steps"]
    checkout_steps = [
        step
        for step in all_steps
        if step.get("uses", "").startswith("actions/checkout@")
    ]
    upload_steps = [
        step
        for step in all_steps
        if step.get("uses", "").startswith("actions/upload-artifact@")
    ]

    assert checkout_steps
    assert upload_steps
    assert all(step["uses"] == "actions/checkout@v5" for step in checkout_steps)
    assert all(step["uses"] == "actions/upload-artifact@v6" for step in upload_steps)
