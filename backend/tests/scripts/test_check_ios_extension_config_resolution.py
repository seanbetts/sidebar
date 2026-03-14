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
validate_built_macos_widget_artifacts = (
    CONFIG_CHECK_MODULE.validate_built_macos_widget_artifacts
)


def _create_widget_app_bundle(tmp_path: Path) -> dict[str, Path]:
    """Create a minimal macOS sideBar.app widget bundle layout for tests."""
    app = tmp_path / "sideBar.app"
    appex = app / "Contents" / "PlugIns" / "sideBarWidgetsExtension.appex"
    widget_macos = appex / "Contents" / "MacOS"
    frameworks = app / "Contents" / "Frameworks"
    shared_framework = frameworks / "sideBarShared.framework"
    widget_executable = widget_macos / "sideBarWidgetsExtension"
    widget_debug_dylib = widget_macos / "sideBarWidgetsExtension.debug.dylib"

    shared_framework.mkdir(parents=True)
    widget_macos.mkdir(parents=True)
    widget_executable.write_text("binary", encoding="utf-8")
    widget_debug_dylib.write_text("binary", encoding="utf-8")

    return {
        "app": app,
        "appex": appex,
        "shared_framework": shared_framework,
        "widget_executable": widget_executable,
        "widget_debug_dylib": widget_debug_dylib,
    }


def _mock_otool_success(
    monkeypatch,
    *,
    missing_rpath: str | None = None,
    missing_link_for: Path | None = None,
):
    """Mock subprocess.check_output for deterministic otool -l and -L responses."""
    required_rpaths = [
        "@executable_path/Frameworks",
        "@executable_path/../../Frameworks",
        "@executable_path/../../../../Frameworks",
    ]
    if missing_rpath is not None:
        required_rpaths.remove(missing_rpath)
    rpath_output = "\n".join(
        (
            "Load command 21\n"
            "          cmd LC_RPATH\n"
            "      cmdsize 56\n"
            f"         path {entry} (offset 12)"
        )
        for entry in required_rpaths
    )

    def _fake_check_output(command, text, stderr):
        binary_path = Path(command[-1])
        if command[:2] == ["otool", "-l"]:
            return rpath_output
        if command[:2] == ["otool", "-L"]:
            if missing_link_for is not None and binary_path == missing_link_for:
                return "/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1439.100.3)"
            return (
                "@rpath/sideBarShared.framework/Versions/A/sideBarShared "
                "(compatibility version 1.0.0, current version 1.0.0)"
            )
        raise AssertionError(f"unexpected command: {command}")

    monkeypatch.setattr(CONFIG_CHECK_MODULE.subprocess, "check_output", _fake_check_output)


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


def test_validate_extension_config_resolution_resolves_braced_placeholders(
    tmp_path: Path,
) -> None:
    """Validator should resolve ${VAR} placeholders from project settings."""
    base_xcconfig = tmp_path / "SideBar.xcconfig"
    base_xcconfig.write_text(f"{LOCAL_INCLUDE_LINE}\n", encoding="utf-8")

    sentinel_values = CONFIG_CHECK_MODULE.SENTINEL_VALUES
    debug_settings = {
        "INFOPLIST_KEY_API_BASE_URL": "${API_BASE_URL}",
        "INFOPLIST_KEY_SUPABASE_URL": "${SUPABASE_URL}",
        "INFOPLIST_KEY_SUPABASE_ANON_KEY": "${SUPABASE_ANON_KEY}",
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


def test_validate_built_macos_widget_artifacts_rejects_non_sidebar_app_path(tmp_path: Path) -> None:
    """Artifact validation should require a sideBar.app bundle path."""
    app = tmp_path / "NotSideBar.app"
    app.mkdir(parents=True)

    errors = validate_built_macos_widget_artifacts(app_path=app)

    assert errors == [f"{app}: expected built app bundle path ending with 'sideBar.app'"]


def test_validate_built_macos_widget_artifacts_reports_missing_widget_appex(
    tmp_path: Path,
) -> None:
    """Artifact validation should fail when the widget appex is absent."""
    app = tmp_path / "sideBar.app"
    (app / "Contents" / "Frameworks" / "sideBarShared.framework").mkdir(parents=True)

    errors = validate_built_macos_widget_artifacts(app_path=app)

    assert (
        f"{app / 'Contents' / 'PlugIns' / 'sideBarWidgetsExtension.appex'}: missing widget extension bundle"
        in errors
    )


def test_validate_built_macos_widget_artifacts_reports_missing_shared_framework(
    tmp_path: Path,
) -> None:
    """Artifact validation should fail when sideBarShared is not embedded in the app."""
    app = tmp_path / "sideBar.app"
    (app / "Contents" / "PlugIns" / "sideBarWidgetsExtension.appex").mkdir(parents=True)

    errors = validate_built_macos_widget_artifacts(app_path=app)

    assert (
        f"{app / 'Contents' / 'Frameworks' / 'sideBarShared.framework'}: missing app framework"
        in errors
    )


def test_validate_built_macos_widget_artifacts_reports_missing_required_rpath(
    monkeypatch,
    tmp_path: Path,
) -> None:
    """Artifact validation should fail when required LC_RPATH entries are missing."""
    paths = _create_widget_app_bundle(tmp_path)
    _mock_otool_success(
        monkeypatch,
        missing_rpath="@executable_path/../../../../Frameworks",
    )

    errors = validate_built_macos_widget_artifacts(app_path=paths["app"])

    unexpected_rpath_errors = [
        error
        for error in errors
        if "missing LC_RPATH entry" in error
        and "@executable_path/../../../../Frameworks" not in error
    ]

    assert (
        f"{paths['widget_executable']}: missing LC_RPATH entry '@executable_path/../../../../Frameworks'"
        in errors
    )
    assert unexpected_rpath_errors == []


def test_validate_built_macos_widget_artifacts_reports_missing_shared_framework_linkage_on_executable(
    monkeypatch,
    tmp_path: Path,
) -> None:
    """Artifact validation should fail when the executable is the only binary and lacks sideBarShared linkage."""
    paths = _create_widget_app_bundle(tmp_path)
    paths["widget_debug_dylib"].unlink()
    _mock_otool_success(monkeypatch, missing_link_for=paths["widget_executable"])

    errors = validate_built_macos_widget_artifacts(app_path=paths["app"])
    assert [error for error in errors if "missing LC_RPATH entry" in error] == []

    assert (
        f"{paths['widget_executable']}: missing linked framework '@rpath/sideBarShared.framework/...'"
        in errors
    )


def test_validate_built_macos_widget_artifacts_accepts_debug_stub_executable_layout(
    monkeypatch,
    tmp_path: Path,
) -> None:
    """Artifact validation should accept the real debug layout where the dylib carries the shared-framework link."""
    paths = _create_widget_app_bundle(tmp_path)
    required_rpaths = "\n".join(
        (
            "Load command 21\n"
            "          cmd LC_RPATH\n"
            "      cmdsize 56\n"
            f"         path {entry} (offset 12)"
        )
        for entry in [
            "@executable_path/Frameworks",
            "@executable_path/../../Frameworks",
            "@executable_path/../../../../Frameworks",
        ]
    )

    def _fake_check_output(command, text, stderr):
        binary_path = Path(command[-1])
        if command[:2] == ["otool", "-l"]:
            return required_rpaths
        if command[:2] == ["otool", "-L"]:
            if binary_path == paths["widget_executable"]:
                return (
                    "@rpath/sideBarWidgetsExtension.debug.dylib "
                    "(compatibility version 0.0.0, current version 0.0.0)"
                )
            if binary_path == paths["widget_debug_dylib"]:
                return (
                    "@rpath/sideBarShared.framework/Versions/A/sideBarShared "
                    "(compatibility version 1.0.0, current version 1.0.0)"
                )
        raise AssertionError(f"unexpected command: {command}")

    monkeypatch.setattr(CONFIG_CHECK_MODULE.subprocess, "check_output", _fake_check_output)

    errors = validate_built_macos_widget_artifacts(app_path=paths["app"])

    assert errors == []


def test_validate_built_macos_widget_artifacts_reports_missing_shared_framework_linkage_on_debug_dylib(
    monkeypatch,
    tmp_path: Path,
) -> None:
    """Artifact validation should fail when widget debug dylib lacks @rpath sideBarShared linkage."""
    paths = _create_widget_app_bundle(tmp_path)
    _mock_otool_success(monkeypatch, missing_link_for=paths["widget_debug_dylib"])

    errors = validate_built_macos_widget_artifacts(app_path=paths["app"])
    assert [error for error in errors if "missing LC_RPATH entry" in error] == []

    assert (
        f"{paths['widget_debug_dylib']}: missing linked framework '@rpath/sideBarShared.framework/...'"
        in errors
    )


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
