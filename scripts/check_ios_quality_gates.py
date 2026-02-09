#!/usr/bin/env python3
"""Enforce iOS hard quality gates from an xcresult bundle."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def load_config(path: Path) -> dict:
    """Load quality gate configuration from JSON."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover
        raise RuntimeError(f"Failed to load config at {path}: {exc}") from exc


def run_xccov(xcresult_path: Path) -> dict:
    """Return the parsed `xccov` JSON report for an xcresult bundle."""
    command = [
        "xcrun",
        "xccov",
        "view",
        "--report",
        "--json",
        str(xcresult_path),
    ]
    try:
        output = subprocess.check_output(command, text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Failed to run xccov: {exc}") from exc
    return json.loads(output)


def extract_coverage_by_target(xccov_report: dict) -> dict[str, float]:
    """Map target name to line coverage percentage."""
    result: dict[str, float] = {}
    for target in xccov_report.get("targets", []):
        name = target.get("name")
        line_coverage = target.get("lineCoverage")
        if not isinstance(name, str) or not isinstance(line_coverage, (int, float)):
            continue
        result[name] = float(line_coverage) * 100.0
    return result


def count_deterministic_ui_tests(
    root: Path,
    ui_test_paths: list[str],
    excluded_test_names: set[str],
) -> int:
    """Count non-template UI test methods in configured UI test folders."""
    test_name_re = re.compile(r"^\s*func\s+(test[A-Za-z0-9_]+)\s*\(")
    discovered: set[str] = set()

    for relative_path in ui_test_paths:
        path = root / relative_path
        if not path.exists():
            continue
        for swift_file in path.rglob("*.swift"):
            text = swift_file.read_text(encoding="utf-8")
            for line in text.splitlines():
                match = test_name_re.match(line)
                if not match:
                    continue
                name = match.group(1)
                if name in excluded_test_names:
                    continue
                discovered.add(name)
    return len(discovered)


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def main() -> int:
    """Run iOS hard quality gate checks and return process exit code."""
    parser = argparse.ArgumentParser(
        description="Check iOS coverage and UI journey quality gates."
    )
    parser.add_argument(
        "--xcresult",
        required=True,
        type=Path,
        help="Path to .xcresult bundle",
    )
    parser.add_argument(
        "--config",
        default=Path("scripts/ios_quality_gates.json"),
        type=Path,
        help="Path to quality-gates JSON config",
    )
    parser.add_argument(
        "--repo-root",
        default=Path(__file__).resolve().parents[1],
        type=Path,
        help="Repository root path",
    )
    args = parser.parse_args()

    config = load_config(args.config)
    thresholds: dict[str, float] = config.get("coverage_thresholds", {})
    baseline_thresholds: dict[str, float] = config.get(
        "baseline_coverage_thresholds", {}
    )
    max_drop_pct_points = float(config.get("max_drop_pct_points", 0.0))
    min_ui_tests = int(config.get("minimum_deterministic_ui_journey_tests", 0))
    ui_test_paths = list(config.get("ui_test_paths", ["ios/sideBar/sideBarUITests"]))
    excluded = set(config.get("excluded_ui_test_names", []))

    report = run_xccov(args.xcresult)
    coverage_by_target = extract_coverage_by_target(report)

    failures: list[str] = []

    emit("Coverage gates:")
    for target_name, threshold in thresholds.items():
        actual = coverage_by_target.get(target_name)
        if actual is None:
            failures.append(f"Missing coverage target in report: {target_name}")
            continue
        emit(f"- {target_name}: {actual:.2f}% (required >= {threshold:.2f}%)")
        if actual < float(threshold):
            required = float(threshold)
            failures.append(
                f"{target_name} coverage {actual:.2f}% "
                f"is below threshold {required:.2f}%"
            )

    if baseline_thresholds and max_drop_pct_points > 0:
        emit("Baseline drop gates:")
        for target_name, baseline in baseline_thresholds.items():
            actual = coverage_by_target.get(target_name)
            if actual is None:
                failures.append(f"Missing baseline target in report: {target_name}")
                continue
            minimum_allowed = float(baseline) - max_drop_pct_points
            emit(
                f"- {target_name}: {actual:.2f}% "
                f"(baseline {float(baseline):.2f}%, "
                f"max drop {max_drop_pct_points:.2f}pp)"
            )
            if actual < minimum_allowed:
                failures.append(
                    f"{target_name} coverage {actual:.2f}% dropped more than "
                    f"{max_drop_pct_points:.2f}pp from baseline {float(baseline):.2f}%"
                )

    ui_test_count = count_deterministic_ui_tests(
        root=args.repo_root,
        ui_test_paths=ui_test_paths,
        excluded_test_names=excluded,
    )
    emit(
        "Deterministic UI journey tests: "
        f"{ui_test_count} (required >= {min_ui_tests})"
    )
    if ui_test_count < min_ui_tests:
        failures.append(
            "Deterministic UI journey tests "
            f"{ui_test_count} is below required minimum {min_ui_tests}"
        )

    if failures:
        emit("\nQuality gate failures:")
        for failure in failures:
            emit(f"- {failure}")
        return 1

    emit("\nAll iOS quality gates passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
