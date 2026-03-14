#!/usr/bin/env python3
"""Validate Apple extension config wiring for config values and embedded frameworks."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = REPO_ROOT / "ios/sideBar/sideBar.xcodeproj"
BASE_XCCONFIG_PATH = REPO_ROOT / "ios/sideBar/Config/SideBar.xcconfig"
PBXPROJ_PATH = PROJECT_PATH / "project.pbxproj"

TARGETS = (
    "ShareExtension",
    "sideBarWidgetsExtension",
    "sideBar Safari Extension",
    "sideBar Safari Extension (macOS)",
    "sideBar Safari Extension (macOS) Extension",
)

DISALLOWED_FRAMEWORK_EMBED_TARGETS = (
    "ShareExtension",
    "sideBarWidgetsExtension",
    "sideBar Safari Extension",
    "sideBar Safari Extension (macOS) Extension",
)

SHARED_FRAMEWORK_PATH = "sideBarShared.framework"

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


def parse_xcconfig_values(xcconfig_text: str) -> dict[str, str]:
    """Parse key/value pairs from an xcconfig string."""
    values: dict[str, str] = {}
    for raw_line in xcconfig_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//") or line.startswith("#include"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = normalize_value(value)
    return values


def parse_build_settings(output: str) -> dict[str, str]:
    """Parse xcodebuild-style KEY = VALUE output into normalized settings."""
    settings: dict[str, str] = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        settings[key.strip()] = normalize_value(value)
    return settings


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


def load_pbxproj_objects(pbxproj_path: Path) -> dict[str, dict[str, object]]:
    """Return the parsed pbxproj objects map via plutil JSON conversion."""
    command = ["plutil", "-convert", "json", "-o", "-", str(pbxproj_path)]
    try:
        output = subprocess.check_output(command, text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            f"plutil failed for '{pbxproj_path}' with exit {exc.returncode}:\n{exc.output}"
        ) from exc

    payload = json.loads(output)
    objects = payload.get("objects")
    if not isinstance(objects, dict):
        raise RuntimeError(f"{pbxproj_path}: missing parsed pbxproj objects")
    return objects


def configuration_settings_for_target(
    *,
    objects: dict[str, dict[str, object]],
    target: str,
    configuration: str,
) -> dict[str, str]:
    """Return normalized build settings for a target configuration."""
    target_id = None
    for object_id, value in objects.items():
        if value.get("isa") != "PBXNativeTarget":
            continue
        if value.get("name") == target:
            target_id = object_id
            break

    if target_id is None:
        raise RuntimeError(f"Missing PBXNativeTarget for '{target}'")

    configuration_list_id = objects[target_id].get("buildConfigurationList")
    configuration_list = objects.get(str(configuration_list_id), {})
    build_configuration_ids = configuration_list.get("buildConfigurations", [])
    if not isinstance(build_configuration_ids, list):
        raise RuntimeError(f"{target}: invalid build configuration list")

    for build_configuration_id in build_configuration_ids:
        config = objects.get(str(build_configuration_id), {})
        if config.get("isa") != "XCBuildConfiguration":
            continue
        if config.get("name") != configuration:
            continue
        build_settings = config.get("buildSettings", {})
        if not isinstance(build_settings, dict):
            raise RuntimeError(f"{target}: invalid build settings for {configuration}")
        return {
            key: normalize_value(str(value))
            for key, value in build_settings.items()
        }

    raise RuntimeError(f"{target}: missing {configuration} build configuration")


def target_object_for_name(
    *,
    objects: dict[str, dict[str, object]],
    target: str,
) -> dict[str, object]:
    """Return the PBXNativeTarget object for a target name."""
    for value in objects.values():
        if value.get("isa") != "PBXNativeTarget":
            continue
        if value.get("name") == target:
            return value

    raise RuntimeError(f"Missing PBXNativeTarget for '{target}'")


def evaluate_embedded_framework_expectations(
    *,
    objects: dict[str, dict[str, object]],
    target: str,
) -> list[str]:
    """Return validation errors for extension targets that disallow embedding sideBarShared."""
    target_object = target_object_for_name(objects=objects, target=target)
    build_phase_ids = target_object.get("buildPhases", [])
    if not isinstance(build_phase_ids, list):
        return [f"{target}: invalid build phase list"]

    for build_phase_id in build_phase_ids:
        build_phase = objects.get(str(build_phase_id), {})
        if build_phase.get("isa") != "PBXCopyFilesBuildPhase":
            continue
        if str(build_phase.get("dstSubfolderSpec")) != "10":
            continue

        file_ids = build_phase.get("files", [])
        if not isinstance(file_ids, list):
            continue

        for file_id in file_ids:
            build_file = objects.get(str(file_id), {})
            if build_file.get("isa") != "PBXBuildFile":
                continue
            file_ref = objects.get(str(build_file.get("fileRef")), {})
            if file_ref.get("path") == SHARED_FRAMEWORK_PATH:
                return [
                    (
                        f"{target}: disallowed embedded framework copy phase for "
                        f"'{SHARED_FRAMEWORK_PATH}'"
                    )
                ]

    return []


def project_configuration_settings(
    *,
    objects: dict[str, dict[str, object]],
    configuration: str,
) -> dict[str, str]:
    """Return normalized project-level build settings for a configuration."""
    root_object_id = next(
        (
            object_id
            for object_id, value in objects.items()
            if value.get("isa") == "PBXProject"
        ),
        None,
    )
    if root_object_id is None:
        raise RuntimeError("Missing PBXProject object")

    configuration_list_id = objects[root_object_id].get("buildConfigurationList")
    configuration_list = objects.get(str(configuration_list_id), {})
    build_configuration_ids = configuration_list.get("buildConfigurations", [])
    if not isinstance(build_configuration_ids, list):
        raise RuntimeError("Invalid project build configuration list")

    for build_configuration_id in build_configuration_ids:
        config = objects.get(str(build_configuration_id), {})
        if config.get("isa") != "XCBuildConfiguration":
            continue
        if config.get("name") != configuration:
            continue
        build_settings = config.get("buildSettings", {})
        if not isinstance(build_settings, dict):
            raise RuntimeError(f"Invalid project build settings for {configuration}")
        return {
            key: normalize_value(str(value))
            for key, value in build_settings.items()
        }

    raise RuntimeError(f"Missing project {configuration} build configuration")


def resolve_value(
    key: str,
    *,
    settings: dict[str, str],
    xcconfig_values: dict[str, str],
    local_overrides: dict[str, str],
    seen: set[str] | None = None,
) -> str | None:
    """Resolve a build setting through target/project settings and xcconfig overrides."""
    if seen is None:
        seen = set()
    if key in seen:
        return None
    seen = seen | {key}

    raw_value = settings.get(key)
    if raw_value is None:
        raw_value = local_overrides.get(key)
    if raw_value is None:
        raw_value = xcconfig_values.get(key)
    if raw_value is None:
        return None

    normalized = normalize_value(raw_value)
    if "$(" not in normalized and "${" not in normalized:
        return normalized

    resolved = normalized
    for source_key in set(settings) | set(xcconfig_values) | set(local_overrides):
        token = f"$({source_key})"
        if token not in resolved:
            continue
        replacement = resolve_value(
            source_key,
            settings=settings,
            xcconfig_values=xcconfig_values,
            local_overrides=local_overrides,
            seen=seen,
        )
        if replacement is None:
            continue
        resolved = resolved.replace(token, replacement)

    return normalize_value(resolved)


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


def validate_extension_config_resolution(
    *,
    pbxproj_path: Path,
    base_xcconfig_path: Path,
    configuration: str,
    targets: tuple[str, ...],
) -> list[str]:
    """Validate Safari extension config wiring and return all discovered errors."""
    errors: list[str] = []

    base_text = base_xcconfig_path.read_text(encoding="utf-8")
    xcconfig_values = parse_xcconfig_values(base_text)
    if not has_relative_local_include(base_text):
        errors.append(
            f"{base_xcconfig_path}: expected relative include line `{LOCAL_INCLUDE_LINE}`"
        )

    objects = load_pbxproj_objects(pbxproj_path)
    project_settings = project_configuration_settings(
        objects=objects,
        configuration=configuration,
    )

    for target in targets:
        target_settings = configuration_settings_for_target(
            objects=objects,
            target=target,
            configuration=configuration,
        )
        settings = {**project_settings, **target_settings}
        expected_keys = set(SETTING_EXPECTATIONS)
        platform_expectations = PLATFORM_EXPECTATIONS_BY_TARGET.get(target)
        if platform_expectations:
            expected_keys.update(platform_expectations)
        resolved_settings = {
            key: value
            for key in (set(settings) | expected_keys)
            if (value := resolve_value(
                key,
                settings=settings,
                xcconfig_values=xcconfig_values,
                local_overrides=SENTINEL_VALUES,
            )) is not None
        }
        errors.extend(
            evaluate_setting_expectations(
                target=target,
                settings=resolved_settings,
                expectations=SETTING_EXPECTATIONS,
            )
        )
        if platform_expectations:
            errors.extend(
                evaluate_platform_expectations(
                    target=target,
                    settings=resolved_settings,
                    expectations=platform_expectations,
                )
            )
        if target in DISALLOWED_FRAMEWORK_EMBED_TARGETS:
            errors.extend(
                evaluate_embedded_framework_expectations(
                    objects=objects,
                    target=target,
                )
            )

    return errors


def main() -> int:
    """Run the config-resolution check and return a process exit code."""
    parser = argparse.ArgumentParser(
        description=(
            "Check Apple extension project wiring for API/Supabase build settings "
            "and disallowed embedded frameworks."
        )
    )
    parser.add_argument(
        "--pbxproj",
        type=Path,
        default=PBXPROJ_PATH,
        help="Path to sideBar.xcodeproj/project.pbxproj",
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

    if not args.pbxproj.exists():
        emit(f"Missing pbxproj: {args.pbxproj}")
        return 1

    if not args.base_xcconfig.exists():
        emit(f"Missing xcconfig: {args.base_xcconfig}")
        return 1

    try:
        errors = validate_extension_config_resolution(
            pbxproj_path=args.pbxproj,
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

    emit("Apple extension config-resolution check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
