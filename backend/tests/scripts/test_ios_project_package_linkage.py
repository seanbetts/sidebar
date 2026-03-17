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


def _debug_build_settings(*, pbxproj_text: str, target_name: str) -> str:
    """Return the raw Debug buildSettings block for one target."""
    config_list_id = _build_config_list_id(pbxproj_text=pbxproj_text, target_name=target_name)
    config_list_match = re.search(
        rf"\t\t{config_list_id} /\* .*? \*/ = \{{\n.*?\t\t\tbuildConfigurations = \(\n(?P<body>.*?)\t\t\t\);\n.*?\t\t\}};",
        pbxproj_text,
        re.DOTALL,
    )
    assert config_list_match is not None, f"Missing XCConfigurationList for {target_name}"
    config_ids = re.findall(r"\t\t\t\t([A-F0-9]+) /\* (Debug|Release) \*/", config_list_match.group("body"))
    debug_config_id = next((config_id for config_id, name in config_ids if name == "Debug"), None)
    assert debug_config_id is not None, f"Missing Debug config for {target_name}"

    config_match = re.search(
        rf"\t\t{debug_config_id} /\* Debug \*/ = \{{\n.*?\t\t\tbuildSettings = \{{\n(?P<body>.*?)\t\t\t\}};\n\t\t\tname = Debug;\n\t\t\}};",
        pbxproj_text,
        re.DOTALL,
    )
    assert config_match is not None, f"Missing Debug build settings for {target_name}"
    return config_match.group("body")


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
        build_settings = _debug_build_settings(
            pbxproj_text=pbxproj_text,
            target_name=target_name,
        )
        assert "ENABLE_DEBUG_DYLIB = NO;" in build_settings
