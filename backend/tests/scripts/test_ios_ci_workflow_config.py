"""Regression tests for the committed iOS CI lane configuration."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ios-ci.yml"
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


def _load_ios_ci_matrix() -> list[dict[str, str]]:
    """Return the configured iOS test matrix entries from the workflow."""
    workflow = yaml.load(WORKFLOW_PATH.read_text(), Loader=yaml.BaseLoader)
    return workflow["jobs"]["ios_test_matrix"]["strategy"]["matrix"]["include"]


def _matrix_entry(entry_id: str) -> dict[str, str]:
    """Return the workflow matrix row for a given lane id."""
    for entry in _load_ios_ci_matrix():
        if entry["id"] == entry_id:
            return entry
    raise AssertionError(f"Missing iOS CI matrix entry: {entry_id}")


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


def test_ipad_lane_configuration_validates_against_committed_scheme() -> None:
    """The iPad lane should resolve to a UI-capable test target."""
    lane = _matrix_entry("ipad")
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
    assert effective_targets == ["sideBarUITests"]


def test_sidebar_scheme_keeps_extension_tests_available_for_fast_lane() -> None:
    """The default `sideBar` scheme should expose extension coverage tests."""
    assert "ShareExtensionTests" in read_scheme_test_targets(
        XCODE_PROJECT_PATH,
        "sideBar",
    )


def test_apple_fast_plan_keeps_share_extension_tests_enabled() -> None:
    """The fast plan should include extension coverage tests for coverage gates."""
    assert "ShareExtensionTests" in _test_target_names_from_plan(APPLE_FAST_PLAN_PATH)
