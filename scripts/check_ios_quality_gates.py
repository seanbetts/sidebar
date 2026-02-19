#!/usr/bin/env python3
"""Enforce iOS hard quality gates from an xcresult bundle."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse


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


def run_xcresulttool(xcresult_path: Path) -> dict:
    """Return parsed xcresult JSON payload using `xcresulttool`."""
    command = [
        "xcrun",
        "xcresulttool",
        "get",
        "--legacy",
        "--format",
        "json",
        "--path",
        str(xcresult_path),
    ]
    try:
        output = subprocess.check_output(command, text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Failed to run xcresulttool: {exc}") from exc
    return json.loads(output)


def iter_warning_summaries(node: object) -> list[dict]:
    """Collect warning summary objects recursively from xcresult JSON."""
    summaries: list[dict] = []
    if isinstance(node, dict):
        warning_summaries = node.get("warningSummaries")
        if isinstance(warning_summaries, dict):
            values = warning_summaries.get("_values")
            if isinstance(values, list):
                summaries.extend(item for item in values if isinstance(item, dict))
        for value in node.values():
            summaries.extend(iter_warning_summaries(value))
    elif isinstance(node, list):
        for value in node:
            summaries.extend(iter_warning_summaries(value))
    return summaries


def parse_document_location(location_url: str | None) -> tuple[str | None, int | None]:
    """Return `(path, line)` from xcresult location URL if available."""
    if not location_url:
        return None, None

    parsed = urlparse(location_url)
    file_path = unquote(parsed.path) if parsed.scheme == "file" else location_url

    line: int | None = None
    if parsed.fragment:
        fragments = parse_qs(parsed.fragment)
        start_line = fragments.get("StartingLineNumber", [])
        if start_line:
            try:
                line = int(start_line[0])
            except ValueError:
                line = None
    return file_path, line


def collect_warning_entries(xcresult_payload: dict) -> list[dict[str, object]]:
    """Extract deduplicated warning entries from an xcresult payload."""
    entries: list[dict[str, object]] = []
    seen: set[tuple[str, str | None, int | None]] = set()

    for summary in iter_warning_summaries(xcresult_payload):
        message = (
            summary.get("message", {}).get("_value")
            if isinstance(summary.get("message"), dict)
            else None
        )
        if not isinstance(message, str):
            continue

        location_url = None
        location_obj = summary.get("documentLocationInCreatingWorkspace")
        if isinstance(location_obj, dict):
            url_obj = location_obj.get("url")
            if isinstance(url_obj, dict):
                raw = url_obj.get("_value")
                if isinstance(raw, str):
                    location_url = raw

        path, line = parse_document_location(location_url)
        key = (message, path, line)
        if key in seen:
            continue
        seen.add(key)
        entries.append(
            {
                "message": message,
                "path": path,
                "line": line,
            }
        )
    return entries


def is_warning_in_scope(
    warning: dict[str, object],
    include_path_contains: list[str],
    exclude_path_contains: list[str],
    exclude_message_regexes: list[re.Pattern[str]],
) -> bool:
    """Return true when warning is subject to gating policy."""
    message = warning.get("message")
    if not isinstance(message, str):
        return False

    path_obj = warning.get("path")
    path = path_obj if isinstance(path_obj, str) else None

    if include_path_contains:
        if not path:
            return False
        if not any(fragment in path for fragment in include_path_contains):
            return False

    if path and any(fragment in path for fragment in exclude_path_contains):
        return False

    return not any(regex.search(message) for regex in exclude_message_regexes)


def evaluate_warning_gates(
    xcresult_path: Path,
    warning_config: dict,
) -> tuple[int, list[str]]:
    """Evaluate warning-gate config and return `(scoped_count, failures)`."""
    max_warnings = int(warning_config.get("max_warnings", 0))
    include_path_contains = list(warning_config.get("include_path_contains", []))
    exclude_path_contains = list(warning_config.get("exclude_path_contains", []))
    exclude_message_regexes = [
        re.compile(pattern)
        for pattern in warning_config.get("exclude_message_regexes", [])
    ]

    xcresult_payload = run_xcresulttool(xcresult_path)
    warnings = collect_warning_entries(xcresult_payload)
    scoped_warnings = [
        warning
        for warning in warnings
        if is_warning_in_scope(
            warning=warning,
            include_path_contains=include_path_contains,
            exclude_path_contains=exclude_path_contains,
            exclude_message_regexes=exclude_message_regexes,
        )
    ]

    emit("Warning gates:")
    emit(f"- scoped warnings: {len(scoped_warnings)} (allowed <= {max_warnings})")
    if scoped_warnings:
        emit("- warning details:")
        for warning in scoped_warnings:
            path = warning.get("path")
            line = warning.get("line")
            message = warning.get("message")
            if isinstance(path, str) and isinstance(line, int):
                location = f"{path}:{line}"
            elif isinstance(path, str):
                location = path
            else:
                location = "<no-file-location>"
            emit(f"  - {location}: {message}")

    failures: list[str] = []
    if len(scoped_warnings) > max_warnings:
        failures.append(
            "Scoped iOS warnings "
            f"{len(scoped_warnings)} exceed allowed maximum {max_warnings}"
        )
    return len(scoped_warnings), failures


def extract_coverage_by_target(xccov_report: dict) -> dict[str, float]:
    """Map target name to line coverage percentage."""
    result: dict[str, float] = {}
    for target in xccov_report.get("targets", []):
        name = target.get("name")
        line_coverage = target.get("lineCoverage")
        if not isinstance(name, str) or not isinstance(line_coverage, int | float):
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
    parser.add_argument(
        "--warnings-only",
        action="store_true",
        help="Run warning gates only (skip coverage/UI-count checks).",
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

    failures: list[str] = []
    if args.warnings_only:
        emit("Coverage gates: skipped (--warnings-only)")
        emit("Deterministic UI journey tests: skipped (--warnings-only)")
    else:
        report = run_xccov(args.xcresult)
        coverage_by_target = extract_coverage_by_target(report)

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
                        f"{max_drop_pct_points:.2f}pp from baseline "
                        f"{float(baseline):.2f}%"
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

    warning_config = config.get("warning_gate", {})
    if warning_config:
        _, warning_failures = evaluate_warning_gates(
            xcresult_path=args.xcresult,
            warning_config=warning_config,
        )
        failures.extend(warning_failures)
    else:
        emit("Warning gates: skipped (no warning_gate config)")

    if failures:
        emit("\nQuality gate failures:")
        for failure in failures:
            emit(f"- {failure}")
        return 1

    emit("\nAll iOS quality gates passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
