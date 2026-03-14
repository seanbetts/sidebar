"""Tests for scripts/check_ios_extension_config_resolution.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "check_ios_extension_config_resolution.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "check_ios_extension_config_resolution", MODULE_PATH
)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
CONFIG_CHECK_MODULE = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(CONFIG_CHECK_MODULE)

LOCAL_INCLUDE_LINE = CONFIG_CHECK_MODULE.LOCAL_INCLUDE_LINE

evaluate_setting_expectations = CONFIG_CHECK_MODULE.evaluate_setting_expectations
has_relative_local_include = CONFIG_CHECK_MODULE.has_relative_local_include
main = CONFIG_CHECK_MODULE.main
parse_build_settings = CONFIG_CHECK_MODULE.parse_build_settings
evaluate_platform_expectations = CONFIG_CHECK_MODULE.evaluate_platform_expectations
evaluate_embedded_framework_expectations = (
    CONFIG_CHECK_MODULE.evaluate_embedded_framework_expectations
)
validate_extension_config_resolution = CONFIG_CHECK_MODULE.validate_extension_config_resolution


def test_has_relative_local_include_accepts_expected_line() -> None:
    """Checker should accept a relative local include line."""
    text = f"// comment\n{LOCAL_INCLUDE_LINE}\n"

    assert has_relative_local_include(text) is True


def test_has_relative_local_include_rejects_srcroot_include() -> None:
    """Checker should reject the previous SRCROOT-based include form."""
    text = '#include? "$(SRCROOT)/Config/SideBar.local.xcconfig"\n'

    assert has_relative_local_include(text) is False


def test_parse_build_settings_normalizes_escaped_values() -> None:
    """Parsed build settings should normalize escaped URL values."""
    output = """
        API_BASE_URL = http:\\/\\/127.0.0.1:8001\\/api\\/v1
        INFOPLIST_KEY_API_BASE_URL = http://127.0.0.1:8001/api/v1
    """

    parsed = parse_build_settings(output)

    assert parsed["API_BASE_URL"] == "http://127.0.0.1:8001/api/v1"
    assert parsed["INFOPLIST_KEY_API_BASE_URL"] == "http://127.0.0.1:8001/api/v1"


def test_evaluate_setting_expectations_reports_unresolved_value() -> None:
    """Unresolved placeholder values should produce actionable failures."""
    errors = evaluate_setting_expectations(
        target="sideBar Safari Extension",
        settings={"API_BASE_URL": "$(API_BASE_URL)"},
        expectations={"API_BASE_URL": "https://example.invalid/api"},
    )

    assert len(errors) == 1
    assert "unresolved" in errors[0]


def test_validate_extension_config_resolution_resolves_expected_values(
    tmp_path: Path,
) -> None:
    """Validator should resolve target placeholders without requiring extension framework embeds."""
    base_xcconfig = tmp_path / "SideBar.xcconfig"
    base_xcconfig.write_text(f"{LOCAL_INCLUDE_LINE}\n", encoding="utf-8")

    sentinel_values = CONFIG_CHECK_MODULE.SENTINEL_VALUES
    debug_settings = {
        "INFOPLIST_KEY_API_BASE_URL": "$(API_BASE_URL)",
        "INFOPLIST_KEY_SUPABASE_URL": "$(SUPABASE_URL)",
        "INFOPLIST_KEY_SUPABASE_ANON_KEY": "$(SUPABASE_ANON_KEY)",
        "APP_GROUP_ID": "group.ai.sidebar.sidebar",
        "INFOPLIST_KEY_APP_GROUP_ID": "group.ai.sidebar.sidebar",
    }

    objects = {
        "project": {
            "isa": "PBXProject",
            "buildConfigurationList": "project_configs",
        },
        "project_configs": {
            "isa": "XCConfigurationList",
            "buildConfigurations": ["project_debug"],
        },
        "project_debug": {
            "isa": "XCBuildConfiguration",
            "name": "Debug",
            "buildSettings": {
                "API_BASE_URL": sentinel_values["API_BASE_URL"],
                "SUPABASE_URL": sentinel_values["SUPABASE_URL"],
                "SUPABASE_ANON_KEY": sentinel_values["SUPABASE_ANON_KEY"],
            },
        },
        "target": {
            "isa": "PBXNativeTarget",
            "name": "sideBar Safari Extension",
            "buildConfigurationList": "target_configs",
            "buildPhases": ["frameworks"],
        },
        "target_configs": {
            "isa": "XCConfigurationList",
            "buildConfigurations": ["target_debug"],
        },
        "target_debug": {
            "isa": "XCBuildConfiguration",
            "name": "Debug",
            "buildSettings": debug_settings,
        },
        "frameworks": {
            "isa": "PBXFrameworksBuildPhase",
            "files": [],
        },
    }

    original_loader = CONFIG_CHECK_MODULE.load_pbxproj_objects
    try:
        CONFIG_CHECK_MODULE.load_pbxproj_objects = lambda _path: objects
        errors = validate_extension_config_resolution(
            pbxproj_path=tmp_path / "project.pbxproj",
            base_xcconfig_path=base_xcconfig,
            configuration="Debug",
            targets=("sideBar Safari Extension",),
        )
    finally:
        CONFIG_CHECK_MODULE.load_pbxproj_objects = original_loader

    assert errors == []


def test_evaluate_platform_expectations_reports_non_macos_safari_target_settings() -> None:
    """macOS Safari targets should fail validation when configured for iPhone SDK/platforms."""
    errors = evaluate_platform_expectations(
        target="sideBar Safari Extension (macOS) Extension",
        settings={
            "SDKROOT": "iphoneos",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        },
        expectations={
            "SDKROOT": "macosx",
            "SUPPORTED_PLATFORMS": "macosx",
        },
    )

    assert errors == [
        "sideBar Safari Extension (macOS) Extension: build setting 'SDKROOT' expected 'macosx' but got 'iphoneos'",
        "sideBar Safari Extension (macOS) Extension: build setting 'SUPPORTED_PLATFORMS' expected 'macosx' but got 'iphoneos iphonesimulator'",
    ]


def test_evaluate_embedded_framework_expectations_reports_embedded_framework_copy_phase() -> None:
    """Extension targets should fail validation if sideBarShared is embedded in the appex."""
    objects = {
        "target": {
            "isa": "PBXNativeTarget",
            "name": "sideBarWidgetsExtension",
            "buildPhases": ["embed_phase"],
        },
        "embed_phase": {
            "isa": "PBXCopyFilesBuildPhase",
            "dstSubfolderSpec": "10",
            "files": ["embed_file"],
        },
        "embed_file": {
            "isa": "PBXBuildFile",
            "fileRef": "shared_framework_ref",
        },
        "shared_framework_ref": {
            "isa": "PBXFileReference",
            "path": "sideBarShared.framework",
        },
    }

    errors = evaluate_embedded_framework_expectations(
        objects=objects,
        target="sideBarWidgetsExtension",
    )

    assert errors == [
        "sideBarWidgetsExtension: disallowed embedded framework copy phase for 'sideBarShared.framework'"
    ]


def test_validate_extension_config_resolution_reports_disallowed_embedded_framework(
    tmp_path: Path,
) -> None:
    """Validator should fail when extension targets embed sideBarShared.framework."""
    base_xcconfig = tmp_path / "SideBar.xcconfig"
    base_xcconfig.write_text(f"{LOCAL_INCLUDE_LINE}\n", encoding="utf-8")

    setting_expectations = CONFIG_CHECK_MODULE.SETTING_EXPECTATIONS
    debug_settings = {
        **setting_expectations,
        "APP_GROUP_ID": "group.ai.sidebar.sidebar",
        "INFOPLIST_KEY_APP_GROUP_ID": "group.ai.sidebar.sidebar",
    }

    objects = {
        "project": {
            "isa": "PBXProject",
            "buildConfigurationList": "project_configs",
        },
        "project_configs": {
            "isa": "XCConfigurationList",
            "buildConfigurations": ["project_debug"],
        },
        "project_debug": {
            "isa": "XCBuildConfiguration",
            "name": "Debug",
            "buildSettings": {},
        },
        "target": {
            "isa": "PBXNativeTarget",
            "name": "sideBarWidgetsExtension",
            "buildConfigurationList": "target_configs",
            "buildPhases": ["embed_phase"],
        },
        "target_configs": {
            "isa": "XCConfigurationList",
            "buildConfigurations": ["target_debug"],
        },
        "target_debug": {
            "isa": "XCBuildConfiguration",
            "name": "Debug",
            "buildSettings": debug_settings,
        },
        "embed_phase": {
            "isa": "PBXCopyFilesBuildPhase",
            "dstSubfolderSpec": "10",
            "files": ["embed_file"],
        },
        "embed_file": {
            "isa": "PBXBuildFile",
            "fileRef": "shared_framework_ref",
        },
        "shared_framework_ref": {
            "isa": "PBXFileReference",
            "path": "sideBarShared.framework",
        },
    }

    # Exercise the real validator path with a monkeypatched pbxproj loader.
    original_loader = CONFIG_CHECK_MODULE.load_pbxproj_objects
    try:
        CONFIG_CHECK_MODULE.load_pbxproj_objects = lambda _path: objects
        errors = validate_extension_config_resolution(
            pbxproj_path=tmp_path / "project.pbxproj",
            base_xcconfig_path=base_xcconfig,
            configuration="Debug",
            targets=("sideBarWidgetsExtension",),
        )
    finally:
        CONFIG_CHECK_MODULE.load_pbxproj_objects = original_loader

    assert "sideBarWidgetsExtension: disallowed embedded framework copy phase for 'sideBarShared.framework'" in errors


def test_validate_extension_config_resolution_reports_missing_macos_host_framework_runpath(
    tmp_path: Path,
) -> None:
    """macOS-capable extensions should fail when they cannot load sideBarShared from the host app."""
    base_xcconfig = tmp_path / "SideBar.xcconfig"
    base_xcconfig.write_text(f"{LOCAL_INCLUDE_LINE}\n", encoding="utf-8")

    setting_expectations = CONFIG_CHECK_MODULE.SETTING_EXPECTATIONS
    debug_settings = {
        **setting_expectations,
        "APP_GROUP_ID": "group.ai.sidebar.sidebar",
        "INFOPLIST_KEY_APP_GROUP_ID": "group.ai.sidebar.sidebar",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
        "SDKROOT": "auto",
        "LD_RUNPATH_SEARCH_PATHS": [
            "$(inherited)",
            "@executable_path/Frameworks",
            "@executable_path/../../Frameworks",
        ],
    }

    objects = {
        "project": {
            "isa": "PBXProject",
            "buildConfigurationList": "project_configs",
        },
        "project_configs": {
            "isa": "XCConfigurationList",
            "buildConfigurations": ["project_debug"],
        },
        "project_debug": {
            "isa": "XCBuildConfiguration",
            "name": "Debug",
            "buildSettings": {},
        },
        "target": {
            "isa": "PBXNativeTarget",
            "name": "sideBarWidgetsExtension",
            "buildConfigurationList": "target_configs",
            "buildPhases": ["frameworks"],
        },
        "target_configs": {
            "isa": "XCConfigurationList",
            "buildConfigurations": ["target_debug"],
        },
        "target_debug": {
            "isa": "XCBuildConfiguration",
            "name": "Debug",
            "buildSettings": debug_settings,
        },
        "frameworks": {
            "isa": "PBXFrameworksBuildPhase",
            "files": [],
        },
    }

    original_loader = CONFIG_CHECK_MODULE.load_pbxproj_objects
    try:
        CONFIG_CHECK_MODULE.load_pbxproj_objects = lambda _path: objects
        errors = validate_extension_config_resolution(
            pbxproj_path=tmp_path / "project.pbxproj",
            base_xcconfig_path=base_xcconfig,
            configuration="Debug",
            targets=("sideBarWidgetsExtension",),
        )
    finally:
        CONFIG_CHECK_MODULE.load_pbxproj_objects = original_loader

    assert (
        "sideBarWidgetsExtension: missing build setting "
        "'LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]'"
    ) in errors


def test_main_returns_failure_when_required_files_missing(monkeypatch, tmp_path: Path) -> None:
    """CLI should fail fast for missing project/xcconfig paths."""
    missing_pbxproj = tmp_path / "missing.pbxproj"
    missing_xcconfig = tmp_path / "missing.xcconfig"

    monkeypatch.setattr(
        "sys.argv",
        [
            "check_ios_extension_config_resolution.py",
            "--pbxproj",
            str(missing_pbxproj),
            "--base-xcconfig",
            str(missing_xcconfig),
        ],
    )

    assert main() == 1
