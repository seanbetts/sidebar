"""Regression tests for iOS Xcode package linkage configuration."""

from __future__ import annotations

from pathlib import Path
import re

REPO_ROOT = Path(__file__).parent.parent.parent.parent
PBXPROJ_PATH = REPO_ROOT / "ios" / "sideBar" / "sideBar.xcodeproj" / "project.pbxproj"


def _pbxproj_text() -> str:
    """Return the raw Xcode project file text."""
    return PBXPROJ_PATH.read_text()


def _native_target_block(*, pbxproj_text: str, target_name: str) -> str:
    """Return the PBXNativeTarget block for one target."""
    rendered_target_name = target_name if " " not in target_name else f'"{target_name}"'
    pattern = re.compile(
        rf"\t\t[A-F0-9]+ /\* {re.escape(target_name)} \*/ = \{{\n"
        r"\t\t\tisa = PBXNativeTarget;\n"
        rf"(?P<body>.*?\t\t\tname = {re.escape(rendered_target_name)};\n.*?\t\t\}};)",
        re.DOTALL,
    )
    match = pattern.search(pbxproj_text)
    assert match is not None, f"Missing PBXNativeTarget for {target_name}"
    return match.group(0)


def _package_product_names(*, pbxproj_text: str, target_name: str) -> set[str]:
    """Return package product dependency names for one Xcode target."""
    target_block = _native_target_block(pbxproj_text=pbxproj_text, target_name=target_name)
    match = re.search(
        r"\t\t\tpackageProductDependencies = \(\n(?P<body>.*?)\t\t\t\);",
        target_block,
        re.DOTALL,
    )
    assert match is not None, f"Missing packageProductDependencies for {target_name}"
    body = match.group("body")
    return set(re.findall(r"/\* ([^*]+) \*/", body))


def _build_config_list_id(*, pbxproj_text: str, target_name: str) -> str:
    """Return the XCConfigurationList id for one native target."""
    target_block = _native_target_block(pbxproj_text=pbxproj_text, target_name=target_name)
    match = re.search(
        r'buildConfigurationList = ([A-F0-9]+) /\* Build configuration list for PBXNativeTarget ".*?" \*/;',
        target_block,
    )
    assert match is not None, f"Missing buildConfigurationList for {target_name}"
    return match.group(1)


def _build_settings_for_config(
    *, pbxproj_text: str, target_name: str, config_name: str
) -> str:
    """Return the raw buildSettings block for one target/configuration."""
    config_list_id = _build_config_list_id(pbxproj_text=pbxproj_text, target_name=target_name)
    config_list_match = re.search(
        rf"\t\t{config_list_id} /\* .*? \*/ = \{{\n.*?\t\t\tbuildConfigurations = \(\n(?P<body>.*?)\t\t\t\);\n.*?\t\t\}};",
        pbxproj_text,
        re.DOTALL,
    )
    assert config_list_match is not None, f"Missing XCConfigurationList for {target_name}"
    config_ids = re.findall(r"\t\t\t\t([A-F0-9]+) /\* (Debug|Release) \*/", config_list_match.group("body"))
    target_config_id = next(
        (config_id for config_id, name in config_ids if name == config_name),
        None,
    )
    assert target_config_id is not None, f"Missing {config_name} config for {target_name}"

    config_match = re.search(
        rf"\t\t{target_config_id} /\* {config_name} \*/ = \{{\n.*?\t\t\tbuildSettings = \{{\n(?P<body>.*?)\t\t\t\}};\n\t\t\tname = {config_name};\n\t\t\}};",
        pbxproj_text,
        re.DOTALL,
    )
    assert config_match is not None, f"Missing {config_name} build settings for {target_name}"
    return config_match.group("body")


def _shell_script_build_phase(*, pbxproj_text: str, phase_name: str) -> str:
    """Return the PBXShellScriptBuildPhase block for one named phase."""
    pattern = re.compile(
        rf"\t\t[A-F0-9]+ /\* {re.escape(phase_name)} \*/ = \{{\n"
        r"\t\t\tisa = PBXShellScriptBuildPhase;\n"
        r"(?P<body>.*?\t\t\};)",
        re.DOTALL,
    )
    match = pattern.search(pbxproj_text)
    assert match is not None, f"Missing PBXShellScriptBuildPhase for {phase_name}"
    return match.group(0)


def test_app_targets_do_not_link_redundant_supabase_subproducts() -> None:
    """The app-style targets should not link Supabase and its subproducts together."""
    pbxproj_text = _pbxproj_text()

    expected_disjoint = {"Auth", "Functions", "PostgREST", "Realtime", "Storage"}

    for target_name in ("sideBar", "sideBarLogicHost"):
        product_names = _package_product_names(
            pbxproj_text=pbxproj_text,
            target_name=target_name,
        )

        assert "Supabase" in product_names
        assert expected_disjoint.isdisjoint(product_names)


def test_app_debug_targets_disable_debug_dylib_splitting() -> None:
    """The app debug targets should not split app code into sideBar.debug.dylib."""
    pbxproj_text = _pbxproj_text()

    for target_name in ("sideBar", "sideBarLogicHost"):
        build_settings = _build_settings_for_config(
            pbxproj_text=pbxproj_text,
            target_name=target_name,
            config_name="Debug",
        )
        assert "ENABLE_DEBUG_DYLIB = NO;" in build_settings


def test_extension_debug_targets_emit_debug_dylibs_for_testable_imports() -> None:
    """Extension debug builds should keep debug dylibs for ShareExtensionTests linkage."""
    pbxproj_text = _pbxproj_text()

    for target_name in ("ShareExtension", "sideBarWidgetsExtension", "sideBar Safari Extension"):
        build_settings = _build_settings_for_config(
            pbxproj_text=pbxproj_text,
            target_name=target_name,
            config_name="Debug",
        )
        assert "ENABLE_DEBUG_DYLIB = YES;" in build_settings


def test_share_extension_tests_link_extension_debug_dylibs() -> None:
    """Extension test bundles should link extension debug dylibs."""
    pbxproj_text = _pbxproj_text()

    for config_name in ("Debug", "Release"):
        build_settings = _build_settings_for_config(
            pbxproj_text=pbxproj_text,
            target_name="ShareExtensionTests",
            config_name=config_name,
        )
        assert '"$(BUILT_PRODUCTS_DIR)/ShareExtension.appex/ShareExtension.debug.dylib"' in build_settings
        assert (
            '"$(BUILT_PRODUCTS_DIR)/sideBarWidgetsExtension.appex/'
            'sideBarWidgetsExtension.debug.dylib"'
            in build_settings
        )
        assert (
            '"$(BUILT_PRODUCTS_DIR)/sideBar\\\\ Safari\\\\ Extension.appex/'
            'sideBar\\\\ Safari\\\\ Extension.debug.dylib"'
            in build_settings
        )


def test_swiftlint_build_phase_includes_share_extension_tests() -> None:
    """Xcode SwiftLint should cover extension tests as well as app tests."""
    pbxproj_text = _pbxproj_text()
    swiftlint_phase = _shell_script_build_phase(pbxproj_text=pbxproj_text, phase_name="SwiftLint")

    assert '"$(SRCROOT)/ShareExtensionTests"' in swiftlint_phase
    assert '\\"${SRCROOT}/ShareExtensionTests\\"' in swiftlint_phase
