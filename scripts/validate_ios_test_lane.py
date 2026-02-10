#!/usr/bin/env python3
"""Validate iOS CI test lane configuration before invoking xcodebuild."""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def parse_csv_specs(raw: str) -> list[str]:
    """Parse comma-separated test specs into trimmed non-empty values."""
    if not raw:
        return []
    return [item.strip() for item in raw.split(",") if item.strip()]


def target_from_test_spec(spec: str) -> str:
    """Return the test target portion of an xcodebuild test filter spec."""
    return spec.split("/", maxsplit=1)[0].strip()


def is_target_level_spec(spec: str) -> bool:
    """Return True when a test filter spec refers to a full test target."""
    return "/" not in spec


def read_scheme_test_targets(project: Path, scheme: str) -> list[str]:
    """Read enabled test targets from a shared Xcode scheme."""
    scheme_path = project / "xcshareddata" / "xcschemes" / f"{scheme}.xcscheme"
    if not scheme_path.exists():
        raise FileNotFoundError(
            f"Shared scheme file not found: {scheme_path}. "
            "Ensure the scheme is shared and committed."
        )

    root = ET.parse(scheme_path).getroot()
    test_targets: list[str] = []
    seen: set[str] = set()

    for testable in root.findall("./TestAction/Testables/TestableReference"):
        if testable.get("skipped", "NO") == "YES":
            continue
        buildable = testable.find("./BuildableReference")
        if buildable is None:
            continue
        target_name = (buildable.get("BlueprintName") or "").strip()
        if not target_name or target_name in seen:
            continue
        seen.add(target_name)
        test_targets.append(target_name)

    if not test_targets:
        raise RuntimeError(f"Scheme '{scheme}' has no enabled test targets.")

    return test_targets


def effective_test_targets(
    scheme_targets: list[str], only_specs: list[str], skip_specs: list[str]
) -> list[str]:
    """Resolve effective test targets after applying only-testing and skip-testing."""
    scheme_set = set(scheme_targets)

    only_targets = {target_from_test_spec(spec) for spec in only_specs}
    if only_targets:
        selected = scheme_set.intersection(only_targets)
    else:
        selected = set(scheme_targets)

    skip_target_specs = {
        target_from_test_spec(spec)
        for spec in skip_specs
        if is_target_level_spec(spec)
    }
    selected -= skip_target_specs

    return [target for target in scheme_targets if target in selected]


def platform_from_destination(destination: str) -> str:
    """Infer platform category from xcodebuild destination string."""
    normalized = destination.lower()
    if "platform=macos" in normalized:
        return "macos"
    if "platform=ios simulator" in normalized or "platform=ios" in normalized:
        return "ios"
    return "unknown"


def validate_lane(
    destination: str,
    scheme_targets: list[str],
    effective_targets: list[str],
    allowed_macos_targets: set[str],
) -> list[str]:
    """Return lane validation errors for the given destination and targets."""
    errors: list[str] = []
    platform = platform_from_destination(destination)

    if not effective_targets:
        errors.append("No effective test targets remain after applying only/skip filters.")
        return errors

    if platform == "macos":
        disallowed_scheme_targets = sorted(set(scheme_targets) - allowed_macos_targets)
        if disallowed_scheme_targets:
            errors.append(
                "macOS lane scheme includes unsupported test targets: "
                f"{', '.join(disallowed_scheme_targets)}. "
                f"Allowed targets: {', '.join(sorted(allowed_macos_targets))}."
            )

        disallowed_effective_targets = sorted(
            set(effective_targets) - allowed_macos_targets
        )
        if disallowed_effective_targets:
            errors.append(
                "macOS lane includes disallowed test targets: "
                f"{', '.join(disallowed_effective_targets)}. "
                f"Allowed targets: {', '.join(sorted(allowed_macos_targets))}."
            )

    return errors


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Validate Xcode scheme test targets for a CI lane."
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=Path("ios/sideBar/sideBar.xcodeproj"),
        help="Path to the .xcodeproj directory.",
    )
    parser.add_argument("--scheme", required=True, help="Xcode scheme name.")
    parser.add_argument(
        "--destination",
        required=True,
        help="xcodebuild destination string (e.g., platform=macOS,arch=arm64).",
    )
    parser.add_argument(
        "--only-testing",
        default="",
        help="Comma-separated -only-testing specs used in this lane.",
    )
    parser.add_argument(
        "--skip-testing",
        default="",
        help="Comma-separated -skip-testing specs used in this lane.",
    )
    parser.add_argument(
        "--allowed-macos-targets",
        default="sideBarTests",
        help="Comma-separated test targets allowed on macOS lanes.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Run validation and return process exit code."""
    args = parse_args(argv or sys.argv[1:])

    try:
        scheme_targets = read_scheme_test_targets(args.project, args.scheme)
    except (FileNotFoundError, RuntimeError, ET.ParseError) as exc:
        print(f"Validation failed: {exc}")
        return 1

    only_specs = parse_csv_specs(args.only_testing)
    skip_specs = parse_csv_specs(args.skip_testing)
    effective_targets_list = effective_test_targets(scheme_targets, only_specs, skip_specs)

    allowed_macos_targets = {
        item for item in parse_csv_specs(args.allowed_macos_targets) if item
    }
    if not allowed_macos_targets:
        print("Validation failed: --allowed-macos-targets cannot be empty.")
        return 1

    errors = validate_lane(
        args.destination,
        scheme_targets,
        effective_targets_list,
        allowed_macos_targets,
    )

    print("Lane validation summary:")
    print(f"- Scheme: {args.scheme}")
    print(f"- Destination: {args.destination}")
    print(f"- Scheme test targets: {', '.join(scheme_targets)}")
    print(
        "- Effective test targets: "
        + (", ".join(effective_targets_list) if effective_targets_list else "(none)")
    )

    if errors:
        print("\nLane validation failures:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("\nLane validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
