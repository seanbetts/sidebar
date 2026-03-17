"""Regression tests for iOS Xcode package linkage configuration."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent.parent
PBXPROJ_PATH = REPO_ROOT / "ios" / "sideBar" / "sideBar.xcodeproj" / "project.pbxproj"


def _load_pbxproj_objects() -> dict[str, dict[str, object]]:
    """Return the parsed pbxproj objects map via plutil JSON conversion."""
    output = subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(PBXPROJ_PATH)],
        text=True,
        stderr=subprocess.STDOUT,
    )
    payload = json.loads(output)
    objects = payload.get("objects")
    assert isinstance(objects, dict)
    return objects


def _target_object_for_name(
    *,
    objects: dict[str, dict[str, object]],
    target_name: str,
) -> dict[str, object]:
    """Return the PBXNativeTarget object for a target name."""
    for value in objects.values():
        if value.get("isa") != "PBXNativeTarget":
            continue
        if value.get("name") == target_name:
            return value
    raise AssertionError(f"Missing PBXNativeTarget for {target_name}")


def _package_product_names(
    *,
    objects: dict[str, dict[str, object]],
    target_name: str,
) -> set[str]:
    """Return package product dependency names for one Xcode target."""
    target = _target_object_for_name(objects=objects, target_name=target_name)
    product_ids = target.get("packageProductDependencies", [])
    assert isinstance(product_ids, list)

    names: set[str] = set()
    for product_id in product_ids:
        product = objects.get(str(product_id), {})
        name = product.get("productName")
        assert isinstance(name, str)
        names.add(name)
    return names


def test_app_targets_do_not_link_redundant_supabase_subproducts() -> None:
    """The app-style targets should not link Supabase and its subproducts together."""
    objects = _load_pbxproj_objects()

    expected_disjoint = {"Auth", "Functions", "PostgREST", "Realtime", "Storage"}

    for target_name in ("sideBar", "sideBarLogicHost"):
        product_names = _package_product_names(objects=objects, target_name=target_name)

        assert "Supabase" in product_names
        assert expected_disjoint.isdisjoint(product_names)


def test_app_debug_targets_disable_debug_dylib_splitting() -> None:
    """The app debug targets should not split app code into sideBar.debug.dylib."""
    objects = _load_pbxproj_objects()

    for target_name in ("sideBar", "sideBarLogicHost"):
        target = _target_object_for_name(objects=objects, target_name=target_name)
        build_config_list = objects[str(target["buildConfigurationList"])]
        build_config_ids = build_config_list.get("buildConfigurations", [])
        assert isinstance(build_config_ids, list)

        debug_config = None
        for build_config_id in build_config_ids:
            config = objects[str(build_config_id)]
            if config.get("name") == "Debug":
                debug_config = config
                break

        assert debug_config is not None, f"Missing Debug config for {target_name}"
        build_settings = debug_config.get("buildSettings", {})
        assert isinstance(build_settings, dict)
        assert build_settings.get("ENABLE_DEBUG_DYLIB") == "NO"
