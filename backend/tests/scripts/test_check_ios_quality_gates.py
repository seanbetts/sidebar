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
evaluate_warning_gates = QUALITY_GATES_MODULE.evaluate_warning_gates
main = QUALITY_GATES_MODULE.main


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
            "count_deterministic_ui_tests should not be called in --warnings-only mode"
        )

    monkeypatch.setattr(QUALITY_GATES_MODULE, "run_xccov", _unexpected_xccov_call)
    monkeypatch.setattr(
        QUALITY_GATES_MODULE,
        "count_deterministic_ui_tests",
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
