"""Regression tests for the committed iOS CI workflow split."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
DEV_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ios-ci.yml"
MAIN_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ios-ci-main.yml"
DISPATCH_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ios-ci-dispatch.yml"
XCODE_PROJECT_PATH = REPO_ROOT / "ios" / "sideBar" / "sideBar.xcodeproj"
APPLE_FAST_PLAN_PATH = (
    XCODE_PROJECT_PATH / "xcshareddata" / "xctestplans" / "AppleFast.xctestplan"
)
SIDEBAR_MAC_TESTS_SCHEME_PATH = (
    XCODE_PROJECT_PATH / "xcshareddata" / "xcschemes" / "sideBarMacTests.xcscheme"
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


def _load_workflow(path: Path) -> dict[str, object]:
    """Return a committed GitHub Actions workflow payload."""
    return yaml.load(path.read_text(), Loader=yaml.BaseLoader)


def _dev_workflow() -> dict[str, object]:
    """Return the dev Apple CI workflow."""
    return _load_workflow(DEV_WORKFLOW_PATH)


def _main_workflow() -> dict[str, object]:
    """Return the main Apple CI workflow."""
    return _load_workflow(MAIN_WORKFLOW_PATH)


def _dispatch_workflow() -> dict[str, object]:
    """Return the manual-dispatch Apple CI workflow."""
    return _load_workflow(DISPATCH_WORKFLOW_PATH)


def _job_matrix(workflow: dict[str, object], job_name: str) -> list[dict[str, str]]:
    """Return matrix entries for a named workflow job."""
    return workflow["jobs"][job_name]["strategy"]["matrix"]["include"]


def _dispatch_matrix() -> list[dict[str, str]]:
    """Return the configured manual-dispatch lane matrix."""
    return _job_matrix(_dispatch_workflow(), "ios_test_dispatch")


def _matrix_entry(entry_id: str) -> dict[str, str]:
    """Return a manual-dispatch matrix row by id."""
    for entry in _dispatch_matrix():
        if entry["id"] == entry_id:
            return entry
    raise AssertionError(f"Missing iOS dispatch matrix entry: {entry_id}")


def _matrix_entries_for_lane(lane: str) -> list[dict[str, str]]:
    """Return all manual-dispatch matrix rows for a lane group."""
    return [entry for entry in _dispatch_matrix() if entry.get("lane") == lane]


def _job_step(workflow: dict[str, object], job_name: str, prefix: str) -> dict[str, object]:
    """Return the first step whose name starts with a given prefix."""
    for step in workflow["jobs"][job_name]["steps"]:
        if step.get("name", "").startswith(prefix):
            return step
    raise AssertionError(f"Missing step {prefix!r} in {job_name}")


def _steps_using(workflow: dict[str, object], job_name: str, action_prefix: str) -> list[dict[str, object]]:
    """Return steps using an action prefix within a workflow job."""
    return [
        step
        for step in workflow["jobs"][job_name]["steps"]
        if step.get("uses", "").startswith(action_prefix)
    ]


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
    """The logic lanes should resolve to deterministic tests on every app surface."""
    for lane in _matrix_entries_for_lane("logic"):
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
def test_apple_fast_plan_excludes_share_extension_tests() -> None:
    """The fast plan should stay limited to deterministic app tests."""
    assert _test_target_names_from_plan(APPLE_FAST_PLAN_PATH) == {"sideBarTests"}


def test_sidebar_scheme_is_the_canonical_app_test_scheme() -> None:
    """The shared app-test scheme should only carry the app test bundle."""
    scheme_targets = read_scheme_test_targets(XCODE_PROJECT_PATH, "sideBar")

    assert scheme_targets == ["sideBarTests"]


def test_duplicate_sidebar_macos_test_scheme_is_removed() -> None:
    """The duplicate macOS-only app-test scheme should not remain in the repo."""
    assert not SIDEBAR_MAC_TESTS_SCHEME_PATH.exists()


def test_dev_workflow_triggers_only_on_dev_pushes() -> None:
    """The dev Apple workflow should be scoped to dev pushes."""
    workflow = _dev_workflow()

    assert workflow["name"] == "iOS CI (dev)"
    assert set(workflow["on"]["push"]["branches"]) == {"dev"}
    assert "workflow_dispatch" not in workflow["on"]
    assert "pull_request" not in workflow["on"]


def test_main_workflow_triggers_only_on_main_pushes() -> None:
    """The main Apple workflow should be scoped to main pushes."""
    workflow = _main_workflow()

    assert workflow["name"] == "iOS CI (main)"
    assert set(workflow["on"]["push"]["branches"]) == {"main"}
    assert "workflow_dispatch" not in workflow["on"]
    assert "pull_request" not in workflow["on"]


def test_dispatch_workflow_triggers_only_manually() -> None:
    """The manual Apple workflow should expose lane selection via dispatch only."""
    workflow = _dispatch_workflow()

    assert workflow["name"] == "iOS CI (manual)"
    assert set(workflow["on"]) == {"workflow_dispatch"}


def test_push_workflows_watch_relevant_ios_inputs_and_workflow_files() -> None:
    """Both push workflows should re-run when Apple inputs or workflow files change."""
    expected_paths = {
        "ios/**",
        "scripts/check_ios_architecture_boundaries.py",
        "scripts/ios_architecture_boundaries_baseline.json",
        "scripts/check_ios_doc_comments.py",
        "scripts/validate_ios_test_lane.py",
        "scripts/validate_ios_test_taxonomy.py",
        "scripts/resolve_ios_test_specs.py",
        "scripts/ios_test_taxonomy.json",
        "scripts/check_ios_quality_gates.py",
        "scripts/ios_quality_gates.json",
        "scripts/check-ios-warning-gate.sh",
        "scripts/test-ios.sh",
        ".swiftlint.yml",
        ".github/workflows/ios-ci.yml",
        ".github/workflows/ios-ci-main.yml",
        ".github/workflows/ios-ci-dispatch.yml",
    }

    assert set(_dev_workflow()["on"]["push"]["paths"]) == expected_paths
    assert set(_main_workflow()["on"]["push"]["paths"]) == expected_paths


def test_ios_ci_jobs_define_timeouts() -> None:
    """Self-hosted iOS jobs should not run without a hard timeout."""
    assert _dev_workflow()["jobs"]["ios_quality"]["timeout-minutes"] == "30"
    assert _dev_workflow()["jobs"]["ios_test_dev"]["timeout-minutes"] == "90"
    assert _main_workflow()["jobs"]["ios_test_main"]["timeout-minutes"] == "90"
    assert _dispatch_workflow()["jobs"]["ios_test_dispatch"]["timeout-minutes"] == "90"


def test_dev_workflow_contains_only_quality_and_logic_jobs() -> None:
    """Dev workflow should materialize only the jobs relevant to dev."""
    workflow = _dev_workflow()

    assert set(workflow["jobs"]) == {"ios_quality", "ios_prepare_packages", "ios_test_dev"}
    assert {entry["id"] for entry in _job_matrix(workflow, "ios_test_dev")} == {
        "logic-iphone",
        "logic-ipad",
        "logic-mac",
    }


def test_main_workflow_contains_only_release_jobs() -> None:
    """Main workflow should materialize only the broader release lanes."""
    workflow = _main_workflow()

    assert set(workflow["jobs"]) == {"ios_prepare_packages", "ios_test_main"}
    assert {entry["id"] for entry in _job_matrix(workflow, "ios_test_main")} == {
        "surface",
        "ui",
        "extensions",
    }


def test_dispatch_workflow_contains_all_lane_options() -> None:
    """Manual dispatch should keep every lane available on demand."""
    workflow = _dispatch_workflow()
    options = workflow["on"]["workflow_dispatch"]["inputs"]["lane"]["options"]
    matrix_lanes = {entry["lane"] for entry in _dispatch_matrix()}

    assert set(workflow["jobs"]) == {"ios_prepare_packages", "ios_test_dispatch"}
    assert set(options) == {"all"} | matrix_lanes


def test_ios_ci_logic_lanes_use_sidebar_scheme_across_all_surfaces() -> None:
    """The dev logic lane should run the same scheme on iPhone, iPad, and macOS."""
    logic_entries = _job_matrix(_dev_workflow(), "ios_test_dev")

    assert {entry["scheme"] for entry in logic_entries} == {"sideBar"}
    assert {entry["test_plan"] for entry in logic_entries} == {"AppleFast"}
    assert {entry["destination"] for entry in logic_entries} == {
        "platform=iOS Simulator,name=iPhone 17 Pro",
        "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
        "platform=macOS",
    }


def test_surface_ui_and_extensions_use_expected_schemes() -> None:
    """The broader lanes should stay bound to their intended schemes and plans."""
    assert _matrix_entry("surface")["scheme"] == "sideBar"
    assert _matrix_entry("surface")["test_plan"] == "AppleStateful"
    assert _matrix_entry("ui")["scheme"] == "sideBarUI"
    assert _matrix_entry("ui")["test_plan"] == "AppleUI"
    assert _matrix_entry("extensions")["scheme"] == "sideBarExtensions"
    assert _matrix_entry("extensions")["test_plan"] == "AppleExtensions"


def test_ios_ci_ui_lane_receives_explicit_ui_test_secrets() -> None:
    """The manual UI lane should receive dedicated auth secrets and shared config."""
    run_step = _job_step(_dispatch_workflow(), "ios_test_dispatch", "Run tests")
    env = run_step["env"]

    assert env["IOS_ONLY_TESTING"] == "${{ env.IOS_ONLY_TESTING }}"
    assert env["SIDEBAR_UI_TEST_EMAIL"] == "${{ secrets.SIDEBAR_UI_TEST_EMAIL }}"
    assert env["SIDEBAR_UI_TEST_PASSWORD"] == "${{ secrets.SIDEBAR_UI_TEST_PASSWORD }}"
    assert env["API_BASE_URL"] == "${{ secrets.API_BASE_URL }}"
    assert env["SUPABASE_URL"] == "${{ secrets.SUPABASE_URL }}"
    assert env["SUPABASE_ANON_KEY"] == "${{ secrets.SUPABASE_ANON_KEY }}"


def test_ios_ci_ipad_lanes_use_the_dedicated_pre_push_simulator() -> None:
    """Shared-Mac iPad lanes should route through the dedicated pre-push simulator helper."""
    workflows_and_jobs = [
        (_dev_workflow(), "ios_test_dev"),
        (_main_workflow(), "ios_test_main"),
        (_dispatch_workflow(), "ios_test_dispatch"),
    ]

    for workflow, job_name in workflows_and_jobs:
        env = _job_step(workflow, job_name, "Run tests")["env"]
        assert env["SIDEBAR_PRE_PUSH_MODE"] == "${{ matrix.pre_push_mode || 'NO' }}"
        assert env["SIDEBAR_PRE_PUSH_STATE_DIR"] == "${{ runner.temp }}/pre-push-simulator/${{ matrix.id }}"
        assert env["SIDEBAR_PRE_PUSH_SIMULATOR_NAME"] == "sideBar PrePush iPad"

    dispatch_entries = _dispatch_matrix()
    ipad_entry_ids = {
        entry["id"]
        for entry in dispatch_entries
        if entry["destination"] == "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
    }
    pre_push_entry_ids = {
        entry["id"] for entry in dispatch_entries if entry.get("pre_push_mode") == "YES"
    }
    assert ipad_entry_ids == {"logic-ipad", "ui"}
    assert pre_push_entry_ids == ipad_entry_ids


def test_ios_ci_stores_result_bundles_under_runner_temp() -> None:
    """Per-run Apple artifacts should live under runner temp, not the persistent workspace."""
    workflows_and_jobs = [
        (_dev_workflow(), "ios_test_dev"),
        (_main_workflow(), "ios_test_main"),
        (_dispatch_workflow(), "ios_test_dispatch"),
    ]

    for workflow, job_name in workflows_and_jobs:
        run_step = _job_step(workflow, job_name, "Run tests")
        env = run_step["env"]

        assert env["IOS_RESULT_BUNDLE_PATH"].startswith("${{ runner.temp }}/ios-test-results/")
        assert env["IOS_SIMULATOR_DIAGNOSTICS_DIR"].startswith(
            "${{ runner.temp }}/ios-test-results/"
        )


def test_ios_ci_uses_persistent_lane_derived_data() -> None:
    """Apple lanes should reuse a stable derived-data path per lane to avoid cold package graph setup."""
    workflows_and_jobs = [
        (_dev_workflow(), "ios_test_dev"),
        (_main_workflow(), "ios_test_main"),
        (_dispatch_workflow(), "ios_test_dispatch"),
    ]

    for workflow, job_name in workflows_and_jobs:
        env = _job_step(workflow, job_name, "Run tests")["env"]
        assert env["IOS_DERIVED_DATA_PATH"] == "${{ env.IOS_SHARED_DERIVED_DATA_ROOT }}/${{ matrix.id }}"
        assert env["IOS_CLEAN_DERIVED_DATA"] == "NO"


def test_ios_ci_uses_persistent_swiftpm_cache_paths() -> None:
    """Apple lanes should keep SwiftPM sources outside disposable per-run DerivedData."""
    workflows_and_jobs = [
        (_dev_workflow(), "ios_test_dev"),
        (_main_workflow(), "ios_test_main"),
        (_dispatch_workflow(), "ios_test_dispatch"),
    ]

    for workflow, job_name in workflows_and_jobs:
        env = _job_step(workflow, job_name, "Run tests")["env"]
        assert env["IOS_CLONED_SOURCE_PACKAGES_DIR"] == "${{ env.IOS_CLONED_SOURCE_PACKAGES_DIR }}"
        assert env["IOS_PACKAGE_CACHE_PATH"] == "${{ env.IOS_PACKAGE_CACHE_PATH }}"
        assert env["IOS_PACKAGE_RESOLVE_TIMEOUT_SECONDS"] == "600"


def test_ios_ci_uploads_failure_artifacts_with_short_retention() -> None:
    """Failure artifacts should expire quickly to avoid exhausting GitHub storage."""
    workflows_and_jobs = [
        (_dev_workflow(), "ios_test_dev"),
        (_main_workflow(), "ios_test_main"),
        (_dispatch_workflow(), "ios_test_dispatch"),
    ]

    for workflow, job_name in workflows_and_jobs:
        upload_steps = _steps_using(workflow, job_name, "actions/upload-artifact@")
        assert upload_steps
        for step in upload_steps:
            assert step["with"]["retention-days"] == "1"


def test_ios_ci_always_cleans_runner_test_outputs() -> None:
    """Apple lanes should clean temp result bundles after every run without deleting warm derived data."""
    workflows_and_jobs = [
        (_dev_workflow(), "ios_test_dev"),
        (_main_workflow(), "ios_test_main"),
        (_dispatch_workflow(), "ios_test_dispatch"),
    ]

    for workflow, job_name in workflows_and_jobs:
        cleanup_step = _job_step(workflow, job_name, "Cleanup test outputs")
        cleanup_script = cleanup_step["run"]

        if job_name == "ios_test_dispatch":
            assert cleanup_step["if"] == (
                "${{ always() && (github.event.inputs.lane == 'all' || "
                "github.event.inputs.lane == matrix.lane) }}"
            )
        else:
            assert cleanup_step["if"] == "${{ always() }}"
        assert "${{ runner.temp }}/ios-test-results/" in cleanup_script
        assert "${{ runner.temp }}/../sidebar-deriveddata-" not in cleanup_script


def test_dev_workflow_does_not_collect_or_upload_simulator_diagnostics() -> None:
    """Dev logic lanes should avoid bulky simulator diagnostics on failure."""
    workflow = _dev_workflow()
    run_step = _job_step(workflow, "ios_test_dev", "Run tests")
    upload_steps = _steps_using(workflow, "ios_test_dev", "actions/upload-artifact@")

    assert (
        run_step["env"]["IOS_COLLECT_SIMULATOR_DIAGNOSTICS_ON_FAILURE"] == "NO"
    )
    assert {step["name"] for step in upload_steps} == {"Upload xcresult bundle (${{ matrix.id }})"}


def test_ios_ci_prewarms_packages_before_parallel_lanes() -> None:
    """Apple workflows should warm shared package state once before running test lanes."""
    dev_workflow = _dev_workflow()
    main_workflow = _main_workflow()
    dispatch_workflow = _dispatch_workflow()

    assert dev_workflow["jobs"]["ios_test_dev"]["needs"] == ["ios_quality", "ios_prepare_packages"]
    assert main_workflow["jobs"]["ios_test_main"]["needs"] == ["ios_prepare_packages"]
    assert dispatch_workflow["jobs"]["ios_test_dispatch"]["needs"] == ["ios_prepare_packages"]

    for workflow, job_name in (
        (dev_workflow, "ios_test_dev"),
        (main_workflow, "ios_test_main"),
        (dispatch_workflow, "ios_test_dispatch"),
    ):
        assert (
            _job_step(workflow, job_name, "Run tests")["env"]["IOS_SKIP_PACKAGE_DEPENDENCY_RESOLUTION"]
            == "YES"
        )


def test_ios_ci_configures_shared_machine_cache_paths() -> None:
    """Warm and test jobs should derive their shared Apple cache paths from HOME."""
    workflows_and_jobs = [
        (_dev_workflow(), "ios_prepare_packages"),
        (_dev_workflow(), "ios_test_dev"),
        (_main_workflow(), "ios_prepare_packages"),
        (_main_workflow(), "ios_test_main"),
        (_dispatch_workflow(), "ios_prepare_packages"),
        (_dispatch_workflow(), "ios_test_dispatch"),
    ]

    for workflow, job_name in workflows_and_jobs:
        script = _job_step(workflow, job_name, "Configure shared Apple cache paths")["run"]
        assert '$HOME/Library/Caches/sidebar-ci-apple-tests' in script
        assert 'IOS_CLONED_SOURCE_PACKAGES_DIR=' in script
        assert 'IOS_PACKAGE_CACHE_PATH=' in script


def test_ios_ci_resolves_only_testing_specs_from_taxonomy() -> None:
    """Workflows should derive Apple test specs from the committed taxonomy."""
    dev_step_script = _job_step(_dev_workflow(), "ios_test_dev", "Resolve taxonomy test specs")["run"]
    main_step_script = _job_step(_main_workflow(), "ios_test_main", "Resolve taxonomy test specs")["run"]
    dispatch_step_script = _job_step(
        _dispatch_workflow(),
        "ios_test_dispatch",
        "Resolve taxonomy test specs",
    )["run"]
    matrix = {entry["id"]: entry for entry in _dispatch_matrix()}

    assert "python3 scripts/resolve_ios_test_specs.py" in dev_step_script
    assert "dev_logic" in dev_step_script
    assert "selection=\"${{ matrix.spec_selection_main }}\"" in main_step_script
    assert "selection=\"${{ matrix.spec_selection_main }}\"" in dispatch_step_script
    assert matrix["logic-iphone"]["spec_selection_main"] == "main_logic"
    assert matrix["logic-ipad"]["spec_selection_main"] == "main_logic"
    assert matrix["logic-mac"]["spec_selection_main"] == "main_logic"
    assert matrix["surface"]["spec_selection_main"] == "main_surface"
    assert matrix["extensions"]["spec_selection_main"] == "main_extensions"
    assert matrix["ui"]["spec_selection_main"] == "ui_smoke"


def test_ios_ci_uses_node24_compatible_actions() -> None:
    """The workflows should use action versions that avoid Node 20 deprecation."""
    all_steps = (
        _dev_workflow()["jobs"]["ios_quality"]["steps"]
        + _dev_workflow()["jobs"]["ios_test_dev"]["steps"]
        + _main_workflow()["jobs"]["ios_test_main"]["steps"]
        + _dispatch_workflow()["jobs"]["ios_test_dispatch"]["steps"]
    )
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
    assert {step["uses"] for step in checkout_steps} == {"actions/checkout@v5"}
    assert {step["uses"] for step in upload_steps} == {"actions/upload-artifact@v6"}


def test_apple_workflows_do_not_bootstrap_sentry_with_package_managers() -> None:
    """Hosted Apple jobs should not use Carthage, CocoaPods, or Sentry SwiftPM bootstrap paths."""
    for workflow, job_name in (
        (_dev_workflow(), "ios_prepare_packages"),
        (_main_workflow(), "ios_prepare_packages"),
        (_dispatch_workflow(), "ios_prepare_packages"),
    ):
        serialized = json.dumps(workflow["jobs"][job_name]).lower()

        assert "carthage" not in serialized
        assert "pod install" not in serialized
        assert "sentry-cocoa" not in serialized
