#!/usr/bin/env python3
"""Validate Safari extension config resolution for iOS/macOS extension targets."""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = REPO_ROOT / "ios/sideBar/sideBar.xcodeproj"
BASE_XCCONFIG_PATH = REPO_ROOT / "ios/sideBar/Config/SideBar.xcconfig"

TARGETS = (
    "sideBar Safari Extension",
    "sideBar Safari Extension (macOS)",
    "sideBar Safari Extension (macOS) Extension",
)

PLATFORM_EXPECTATIONS_BY_TARGET = {
    "sideBar Safari Extension (macOS)": {
        "SDKROOT": "macosx",
        "SUPPORTED_PLATFORMS": "macosx",
    },
    "sideBar Safari Extension (macOS) Extension": {
        "SDKROOT": "macosx",
        "SUPPORTED_PLATFORMS": "macosx",
    },
}

SENTINEL_VALUES = {
    "API_BASE_URL": "https://config-resolution.example.invalid/api/v1",
    "SUPABASE_URL": "https://config-resolution.example.invalid",
    "SUPABASE_ANON_KEY": "config-resolution-anon-key",
}

SETTING_EXPECTATIONS = {
    "API_BASE_URL": SENTINEL_VALUES["API_BASE_URL"],
    "SUPABASE_URL": SENTINEL_VALUES["SUPABASE_URL"],
    "SUPABASE_ANON_KEY": SENTINEL_VALUES["SUPABASE_ANON_KEY"],
    "INFOPLIST_KEY_API_BASE_URL": SENTINEL_VALUES["API_BASE_URL"],
    "INFOPLIST_KEY_SUPABASE_URL": SENTINEL_VALUES["SUPABASE_URL"],
    "INFOPLIST_KEY_SUPABASE_ANON_KEY": SENTINEL_VALUES["SUPABASE_ANON_KEY"],
}

LOCAL_INCLUDE_LINE = '#include? "SideBar.local.xcconfig"'


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def normalize_value(value: str) -> str:
    """Normalize escaped xcconfig values for stable comparison."""
    return value.strip().strip('"').replace("\\/", "/")


def normalize_sdkroot_value(value: str) -> str:
    """Collapse resolved SDKROOT paths to stable platform identifiers."""
    normalized = normalize_value(value)
    lowered = normalized.lower()
    if "macosx.platform" in lowered:
        return "macosx"
    if "iphoneos.platform" in lowered:
        return "iphoneos"
    if "iphonesimulator.platform" in lowered:
        return "iphonesimulator"
    return normalized


def has_relative_local_include(xcconfig_text: str) -> bool:
    """Return true if SideBar.xcconfig includes local overrides via relative include."""
    for raw_line in xcconfig_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("//"):
            continue
        if line == LOCAL_INCLUDE_LINE:
            return True
    return False


def parse_build_settings(output: str) -> dict[str, str]:
    """Parse `xcodebuild -showBuildSettings` output into a key/value map."""
    settings: dict[str, str] = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if " = " not in line:
            continue
        key, value = line.split(" = ", 1)
        key = key.strip()
        if not key:
            continue
        settings[key] = normalize_value(value)
    return settings


def run_show_build_settings(
    *,
    project_path: Path,
    target: str,
    configuration: str,
    xcconfig_path: Path,
) -> str:
    """Return build settings output for a target."""
    command = [
        "xcodebuild",
        "-project",
        str(project_path),
        "-target",
        target,
        "-configuration",
        configuration,
        "-xcconfig",
        str(xcconfig_path),
        "-showBuildSettings",
    ]
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            f"xcodebuild failed for target '{target}' with exit {exc.returncode}:\n{exc.output}"
        ) from exc


def evaluate_setting_expectations(
    *,
    target: str,
    settings: dict[str, str],
    expectations: dict[str, str],
) -> list[str]:
    """Return validation errors for expected build settings."""
    errors: list[str] = []
    for key, expected in expectations.items():
        actual = settings.get(key)
        if actual is None:
            errors.append(f"{target}: missing build setting '{key}'")
            continue

        if "$(" in actual or "${" in actual:
            errors.append(f"{target}: build setting '{key}' is unresolved: {actual}")
            continue

        if normalize_value(actual) != normalize_value(expected):
            errors.append(
                f"{target}: build setting '{key}' expected '{expected}' but got '{actual}'"
            )
    return errors


def evaluate_platform_expectations(
    *,
    target: str,
    settings: dict[str, str],
    expectations: dict[str, str],
) -> list[str]:
    """Return validation errors for expected platform build settings."""
    normalized_settings = dict(settings)
    if "SDKROOT" in normalized_settings:
        normalized_settings["SDKROOT"] = normalize_sdkroot_value(normalized_settings["SDKROOT"])

    return evaluate_setting_expectations(
        target=target,
        settings=normalized_settings,
        expectations=expectations,
    )


def write_temp_xcconfig_pair(base_text: str, directory: Path) -> Path:
    """Write SideBar.xcconfig + SideBar.local.xcconfig in a temp directory."""
    base_path = directory / "SideBar.xcconfig"
    local_path = directory / "SideBar.local.xcconfig"
    base_path.write_text(base_text, encoding="utf-8")
    encoded_values = {
        key: value.replace("/", "\\/")
        for key, value in SENTINEL_VALUES.items()
    }
    local_payload = "\n".join(
        [f"{key} = {value}" for key, value in encoded_values.items()]
    )
    local_path.write_text(f"{local_payload}\n", encoding="utf-8")
    return base_path


def validate_extension_config_resolution(
    *,
    project_path: Path,
    base_xcconfig_path: Path,
    configuration: str,
    targets: tuple[str, ...],
) -> list[str]:
    """Validate Safari extension config resolution and return all discovered errors."""
    errors: list[str] = []

    base_text = base_xcconfig_path.read_text(encoding="utf-8")
    if not has_relative_local_include(base_text):
        errors.append(
            f"{base_xcconfig_path}: expected relative include line `{LOCAL_INCLUDE_LINE}`"
        )

    with tempfile.TemporaryDirectory(prefix="sidebar-ios-config-") as temp_dir:
        temp_xcconfig = write_temp_xcconfig_pair(base_text, Path(temp_dir))

        for target in targets:
            output = run_show_build_settings(
                project_path=project_path,
                target=target,
                configuration=configuration,
                xcconfig_path=temp_xcconfig,
            )
            settings = parse_build_settings(output)
            errors.extend(
                evaluate_setting_expectations(
                    target=target,
                    settings=settings,
                    expectations=SETTING_EXPECTATIONS,
                )
            )
            platform_expectations = PLATFORM_EXPECTATIONS_BY_TARGET.get(target)
            if platform_expectations:
                errors.extend(
                    evaluate_platform_expectations(
                        target=target,
                        settings=settings,
                        expectations=platform_expectations,
                    )
                )

    return errors


def main() -> int:
    """Run the config-resolution check and return a process exit code."""
    parser = argparse.ArgumentParser(
        description="Check Safari extension build-setting resolution for API/Supabase keys."
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=PROJECT_PATH,
        help="Path to sideBar.xcodeproj",
    )
    parser.add_argument(
        "--base-xcconfig",
        type=Path,
        default=BASE_XCCONFIG_PATH,
        help="Path to SideBar.xcconfig",
    )
    parser.add_argument(
        "--configuration",
        default="Debug",
        help="Xcode build configuration to validate",
    )
    args = parser.parse_args()

    if not args.project.exists():
        emit(f"Missing project: {args.project}")
        return 1

    if not args.base_xcconfig.exists():
        emit(f"Missing xcconfig: {args.base_xcconfig}")
        return 1

    try:
        errors = validate_extension_config_resolution(
            project_path=args.project,
            base_xcconfig_path=args.base_xcconfig,
            configuration=args.configuration,
            targets=TARGETS,
        )
    except RuntimeError as exc:
        emit(str(exc))
        return 1

    if errors:
        emit("Safari extension config-resolution check failed:")
        for item in errors:
            emit(f"- {item}")
        return 1

    emit("Safari extension config-resolution check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
