"""Tests for iOS warning gates in scripts/check_ios_quality_gates.py."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "check_ios_quality_gates.py"
MODULE_SPEC = importlib.util.spec_from_file_location("check_ios_quality_gates", MODULE_PATH)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
QUALITY_GATES_MODULE = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(QUALITY_GATES_MODULE)

collect_warning_entries = QUALITY_GATES_MODULE.collect_warning_entries
count_executed_ui_tests = QUALITY_GATES_MODULE.count_executed_ui_tests
evaluate_warning_gates = QUALITY_GATES_MODULE.evaluate_warning_gates
main = QUALITY_GATES_MODULE.main
resolve_profile_config = QUALITY_GATES_MODULE.resolve_profile_config


def _warning_summary(message: str, file_path: str, line: int) -> dict:
    """Build an xcresult warning summary entry with location metadata."""
    return {
        "message": {"_value": message},
        "documentLocationInCreatingWorkspace": {
            "url": {
                "_value": (
                    f"file://{file_path}"
                    f"#StartingLineNumber={line}&StartingColumnNumber=1"
                )
            }
        },
    }


def _test_case(name: str, result: str) -> dict:
    """Build a compact xcresult test node for a single test case."""
    return {
        "nodeType": "Test Case",
        "name": name,
        "result": result,
    }


def test_collect_warning_entries_deduplicates_and_extracts_location() -> None:
    """Warnings from multiple xcresult sections should be deduplicated."""
    duplicated_warning = _warning_summary(
        message="Deprecated API usage",
        file_path="/Users/me/repo/ios/sideBar/sideBar/Foo.swift",
        line=42,
    )
    payload = {
        "issues": {"warningSummaries": {"_values": [duplicated_warning]}},
        "actions": {
            "_values": [
                {
                    "actionResult": {
                        "issues": {"warningSummaries": {"_values": [duplicated_warning]}}
                    }
                }
            ]
        },
    }

    entries = collect_warning_entries(payload)

    assert len(entries) == 1
    assert entries[0]["message"] == "Deprecated API usage"
    assert entries[0]["path"] == "/Users/me/repo/ios/sideBar/sideBar/Foo.swift"
    assert entries[0]["line"] == 42


def test_evaluate_warning_gates_scopes_by_path(monkeypatch) -> None:
    """Only warnings inside configured include paths should count."""
    payload = {
        "issues": {
            "warningSummaries": {
                "_values": [
                    _warning_summary(
                        message="Scoped warning",
                        file_path="/Volumes/workspace/repository/ios/sideBar/sideBar/View.swift",
                        line=10,
                    ),
                    _warning_summary(
                        message="Ignored test warning",
                        file_path="/Volumes/workspace/repository/ios/sideBar/sideBarTests/Test.swift",
                        line=12,
                    ),
                ]
            }
        }
    }
    monkeypatch.setattr(QUALITY_GATES_MODULE, "run_xcresulttool", lambda _: payload)

    scoped_count, failures = evaluate_warning_gates(
        xcresult_path=Path("/tmp/fake.xcresult"),
        warning_config={
            "max_warnings": 0,
            "include_path_contains": ["/ios/sideBar/sideBar/"],
            "exclude_path_contains": [],
            "exclude_message_regexes": [],
        },
    )

    assert scoped_count == 1
    assert failures == ["Scoped iOS warnings 1 exceed allowed maximum 0"]


def test_count_executed_ui_tests_counts_non_skipped_ui_test_cases() -> None:
    """Executed UI test count should come from xcresult test results, not source."""
    payload = {
        "testPlanConfigurations": [],
        "devices": [],
        "testNodes": [
            {
                "nodeType": "UI test bundle",
                "name": "sideBarUITests",
                "children": [
                    _test_case("testLogin", "Passed"),
                    _test_case("testStreamingReply", "Failed"),
                    _test_case("testSkippedJourney", "Skipped"),
                ],
            },
            {
                "nodeType": "Unit test bundle",
                "name": "sideBarTests",
                "children": [_test_case("testUnitCoverage", "Passed")],
            },
        ],
    }

    assert count_executed_ui_tests(payload, {"sideBarUITests"}) == 2


def test_resolve_profile_config_merges_selected_profile_over_root() -> None:
    """Profile overrides should replace thresholds while inheriting shared gates."""
    resolved = resolve_profile_config(
        {
            "default_profile": "full",
            "profiles": {
                "full": {
                    "coverage_thresholds": {"sideBar.app": 25.0},
                    "minimum_deterministic_ui_journey_tests": 3,
                },
                "logic": {
                    "coverage_thresholds": {"sideBarShared.framework": 60.0},
                    "minimum_deterministic_ui_journey_tests": 0,
                },
            },
            "warning_gate": {
                "max_warnings": 0,
                "include_path_contains": ["/ios/sideBar/sideBar/"],
            },
        },
        profile="logic",
    )

    assert resolved["coverage_thresholds"] == {"sideBarShared.framework": 60.0}
    assert resolved["minimum_deterministic_ui_journey_tests"] == 0
    assert resolved["warning_gate"]["max_warnings"] == 0


def test_main_logic_profile_accepts_logic_only_xcresult(
    monkeypatch, tmp_path: Path
) -> None:
    """The logic profile should not require app/UI targets from a logic-only xcresult."""
    config_path = tmp_path / "ios_quality_gates.json"
    config_path.write_text(
        json.dumps(
            {
                "default_profile": "full",
                "profiles": {
                    "full": {
                        "coverage_thresholds": {"sideBar.app": 25.0},
                        "baseline_coverage_thresholds": {"sideBar.app": 29.0},
                        "minimum_deterministic_ui_journey_tests": 3,
                    },
                    "logic": {
                        "coverage_thresholds": {"sideBarShared.framework": 60.0},
                        "baseline_coverage_thresholds": {"sideBarShared.framework": 66.0},
                        "minimum_deterministic_ui_journey_tests": 0,
                    },
                },
                "max_drop_pct_points": 1.0,
                "warning_gate": {
                    "max_warnings": 0,
                    "include_path_contains": ["/ios/sideBar/sideBar/"],
                    "exclude_path_contains": [],
                    "exclude_message_regexes": [],
                },
            }
        )
    )

    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xccov",
        lambda _: {
            "targets": [
                {"name": "sideBarShared.framework", "lineCoverage": 0.76},
            ]
        },
    )
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool_tests",
        lambda _: {"testNodes": []},
    )
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool",
        lambda _: {"issues": {"warningSummaries": {"_values": []}}},
    )

    monkeypatch.setattr(
        "sys.argv",
        [
            "check_ios_quality_gates.py",
            "--xcresult",
            str(tmp_path / "logic-only.xcresult"),
            "--config",
            str(config_path),
            "--profile",
            "logic",
        ],
    )

    assert main() == 0


def test_lane_specific_profiles_can_target_disjoint_xcresults() -> None:
    """Lane profiles should require only the targets each workflow lane produces."""
    resolved = resolve_profile_config(
        {
            "default_profile": "full",
            "profiles": {
                "logic": {
                    "coverage_thresholds": {"sideBarShared.framework": 60.0},
                    "minimum_deterministic_ui_journey_tests": 0,
                },
                "surface": {
                    "coverage_thresholds": {
                        "sideBar.app": 25.0,
                        "sideBarShared.framework": 60.0,
                    },
                    "minimum_deterministic_ui_journey_tests": 0,
                },
                "ui": {
                    "coverage_thresholds": {},
                    "minimum_deterministic_ui_journey_tests": 3,
                },
                "extensions": {
                    "coverage_thresholds": {
                        "ShareExtension.appex": 1.0,
                        "sideBarWidgetsExtension.appex": 5.0,
                        "sideBar Safari Extension.appex": 30.0,
                    },
                    "minimum_deterministic_ui_journey_tests": 0,
                },
            },
            "warning_gate": {
                "max_warnings": 0,
                "include_path_contains": ["/ios/sideBar/sideBar/"],
            },
        },
        profile="extensions",
    )

    assert resolved["coverage_thresholds"] == {
        "ShareExtension.appex": 1.0,
        "sideBarWidgetsExtension.appex": 5.0,
        "sideBar Safari Extension.appex": 30.0,
    }
    assert resolved["minimum_deterministic_ui_journey_tests"] == 0


def test_main_fails_when_executed_ui_tests_are_below_minimum(
    monkeypatch, tmp_path: Path
) -> None:
    """The minimum UI journey gate should fail when xcresult shows too few runs."""
    config_path = tmp_path / "ios_quality_gates.json"
    config_path.write_text(
        json.dumps(
            {
                "coverage_thresholds": {"sideBar.app": 10.0},
                "minimum_deterministic_ui_journey_tests": 3,
                "ui_test_target_names": ["sideBarUITests"],
                "warning_gate": {
                    "max_warnings": 0,
                    "include_path_contains": ["/ios/sideBar/sideBar/"],
                    "exclude_path_contains": [],
                    "exclude_message_regexes": [],
                },
            }
        )
    )

    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xccov",
        lambda _: {"targets": [{"name": "sideBar.app", "lineCoverage": 0.2}]},
    )
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool_tests",
        lambda _: {
            "testPlanConfigurations": [],
            "devices": [],
            "testNodes": [
                {
                    "nodeType": "UI test bundle",
                    "name": "sideBarUITests",
                    "children": [
                        _test_case("testLogin", "Passed"),
                        _test_case("testStreamingReply", "Passed"),
                        _test_case("testSkippedJourney", "Skipped"),
                    ],
                }
            ],
        },
    )
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool",
        lambda _: {"issues": {"warningSummaries": {"_values": []}}},
    )

    monkeypatch.setattr(
        "sys.argv",
        [
            "check_ios_quality_gates.py",
            "--xcresult",
            str(tmp_path / "fake.xcresult"),
            "--config",
            str(config_path),
        ],
    )

    assert main() == 1


def test_main_skip_coverage_still_enforces_ui_test_minimum(
    monkeypatch, tmp_path: Path
) -> None:
    """`--skip-coverage` should still enforce executed UI journey minimums."""
    config_path = tmp_path / "ios_quality_gates.json"
    config_path.write_text(
        json.dumps(
            {
                "coverage_thresholds": {"sideBar.app": 80.0},
                "minimum_deterministic_ui_journey_tests": 3,
                "ui_test_target_names": ["sideBarUITests"],
                "warning_gate": {
                    "max_warnings": 0,
                    "include_path_contains": ["/ios/sideBar/sideBar/"],
                    "exclude_path_contains": [],
                    "exclude_message_regexes": [],
                },
            }
        )
    )

    def _unexpected_xccov_call(_: Path) -> dict:  # pragma: no cover - defensive
        raise AssertionError("run_xccov should not be called in --skip-coverage mode")

    monkeypatch.setattr(QUALITY_GATES_MODULE, "run_xccov", _unexpected_xccov_call)
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool_tests",
        lambda _: {
            "testPlanConfigurations": [],
            "devices": [],
            "testNodes": [
                {
                    "nodeType": "UI test bundle",
                    "name": "sideBarUITests",
                    "children": [
                        _test_case("testLogin", "Passed"),
                        _test_case("testStreamingReply", "Passed"),
                    ],
                }
            ],
        },
    )
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool",
        lambda _: {"issues": {"warningSummaries": {"_values": []}}},
    )

    monkeypatch.setattr(
        "sys.argv",
        [
            "check_ios_quality_gates.py",
            "--xcresult",
            str(tmp_path / "fake.xcresult"),
            "--config",
            str(config_path),
            "--skip-coverage",
        ],
    )

    assert main() == 1


def test_main_skip_ui_test_minimum_still_enforces_coverage(
    monkeypatch, tmp_path: Path
) -> None:
    """`--skip-ui-test-minimum` should still enforce coverage thresholds."""
    config_path = tmp_path / "ios_quality_gates.json"
    config_path.write_text(
        json.dumps(
            {
                "coverage_thresholds": {"sideBar.app": 50.0},
                "minimum_deterministic_ui_journey_tests": 99,
                "ui_test_target_names": ["sideBarUITests"],
                "warning_gate": {
                    "max_warnings": 0,
                    "include_path_contains": ["/ios/sideBar/sideBar/"],
                    "exclude_path_contains": [],
                    "exclude_message_regexes": [],
                },
            }
        )
    )

    def _unexpected_ui_count(*_, **__):  # pragma: no cover - defensive
        raise AssertionError(
            "run_xcresulttool_tests should not be called in --skip-ui-test-minimum mode"
        )

    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xccov",
        lambda _: {"targets": [{"name": "sideBar.app", "lineCoverage": 0.2}]},
    )
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool_tests",
        _unexpected_ui_count,
    )
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool",
        lambda _: {"issues": {"warningSummaries": {"_values": []}}},
    )

    monkeypatch.setattr(
        "sys.argv",
        [
            "check_ios_quality_gates.py",
            "--xcresult",
            str(tmp_path / "fake.xcresult"),
            "--config",
            str(config_path),
            "--skip-ui-test-minimum",
        ],
    )

    assert main() == 1


def test_main_warnings_only_skips_coverage_and_ui_checks(
    monkeypatch, tmp_path: Path
) -> None:
    """`--warnings-only` should not call xccov/UI count checks."""
    config_path = tmp_path / "ios_quality_gates.json"
    config_path.write_text(
        json.dumps(
            {
                "coverage_thresholds": {"sideBar.app": 10.0},
                "minimum_deterministic_ui_journey_tests": 99,
                "warning_gate": {
                    "max_warnings": 0,
                    "include_path_contains": ["/ios/sideBar/sideBar/"],
                    "exclude_path_contains": [],
                    "exclude_message_regexes": [],
                },
            }
        )
    )

    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "run_xcresulttool",
        lambda _: {"issues": {"warningSummaries": {"_values": []}}},
    )

    def _unexpected_xccov_call(_: Path) -> dict:  # pragma: no cover - defensive
        raise AssertionError("run_xccov should not be called in --warnings-only mode")

    def _unexpected_ui_count(*_, **__):  # pragma: no cover - defensive
        raise AssertionError(
            "count_executed_ui_tests should not be called in --warnings-only mode"
        )

    monkeypatch.setattr(QUALITY_GATES_MODULE, "run_xccov", _unexpected_xccov_call)
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "count_executed_ui_tests",
        _unexpected_ui_count,
    )

    monkeypatch.setattr(
        "sys.argv",
        [
            "check_ios_quality_gates.py",
            "--xcresult",
            str(tmp_path / "fake.xcresult"),
            "--config",
            str(config_path),
            "--warnings-only",
        ],
    )

    assert main() == 0
