"""Repo-level guardrails for future Apple Sentry reintegration."""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
IOS_ROOT = REPO_ROOT / "ios" / "sideBar"
PBXPROJ = REPO_ROOT / "ios" / "sideBar" / "sideBar.xcodeproj" / "project.pbxproj"
CI_POST_CLONE_SCRIPT = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "ci_post_clone.sh"
CI_POST_XCODEBUILD_SCRIPT = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "ci_post_xcodebuild.sh"
UPLOAD_SCRIPT = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "upload_sentry_dsyms.sh"
BOOTSTRAP = REPO_ROOT / "ios" / "sideBar" / "sideBar" / "App" / "SentryBootstrap.swift"
IOS_APP_DELEGATE = REPO_ROOT / "ios" / "sideBar" / "sideBar" / "App" / "AppLaunchDelegate.swift"
MAC_APP_DELEGATE = REPO_ROOT / "ios" / "sideBar" / "sideBar" / "App" / "MacAppDelegate.swift"


def test_bootstrap_seam_remains_present_and_dependency_injected() -> None:
    bootstrap_contents = BOOTSTRAP.read_text(encoding="utf-8")

    signature_match = re.search(
        r"static func startIfConfigured\((?P<signature>.*?)\)\s*->\s*Bool",
        bootstrap_contents,
        re.DOTALL,
    )

    assert "enum SentryBootstrap" in bootstrap_contents
    assert "protocol SentryBundleInfo" in bootstrap_contents
    assert "protocol SentryBootstrapClient" in bootstrap_contents
    assert signature_match is not None
    assert "config: EnvironmentConfig" in signature_match.group("signature")
    assert "bundle: SentryBundleInfo" in signature_match.group("signature")
    assert "client: SentryBootstrapClient" in signature_match.group("signature")
    assert "static func resetForTesting()" in bootstrap_contents


def test_bootstrap_seam_remains_wired_from_app_entry_points() -> None:
    ios_delegate_contents = IOS_APP_DELEGATE.read_text(encoding="utf-8")
    mac_delegate_contents = MAC_APP_DELEGATE.read_text(encoding="utf-8")

    assert "SentryBootstrap.startIfConfigured(config: config)" in ios_delegate_contents
    assert "SentryBootstrap.startIfConfigured(config: config)" in mac_delegate_contents


def test_ci_and_upload_hooks_remain_explicit_sentry_touchpoints() -> None:
    ci_contents = CI_POST_CLONE_SCRIPT.read_text(encoding="utf-8")
    post_xcodebuild_contents = CI_POST_XCODEBUILD_SCRIPT.read_text(encoding="utf-8")
    script_contents = UPLOAD_SCRIPT.read_text(encoding="utf-8")

    assert "SENTRY_DSN" in ci_contents
    assert r"INFOPLIST_KEY_SENTRY_DSN = \$(SENTRY_DSN)" in ci_contents
    assert "sentry-post-xcodebuild:" in post_xcodebuild_contents
    assert "sentry-dsym-upload:" in script_contents
    assert "set -euo pipefail" in script_contents


def test_swiftpm_remains_disallowed_for_future_apple_sentry_reintegration() -> None:
    assert _has_swift_package_sentry_path() is False


def test_project_allows_at_most_one_future_approved_sentry_dependency_path() -> None:
    active_paths = {
        "cocoapods": _has_cocoapods_sentry_path(),
        "carthage": _has_carthage_sentry_path(),
        "vendored": _has_vendored_sentry_path(),
    }
    selected_paths = [name for name, is_active in active_paths.items() if is_active]

    assert selected_paths == ["vendored"], (
        "Apple Sentry reintegration must rely exclusively on the vendored XCFramework path as the approved dependency, "
        f"found multiple active paths: {selected_paths}"
    )


def test_project_reserves_at_most_one_upload_hook_entry() -> None:
    project_contents = PBXPROJ.read_text(encoding="utf-8")
    assert project_contents.count('name = "Upload Sentry dSYMs";') == 1
    assert "upload_sentry_dsyms.sh" in project_contents


def test_vendored_sdk_is_linked_only_to_main_app_target() -> None:
    project_contents = PBXPROJ.read_text(encoding="utf-8")

    assert "Vendor/Sentry/Sentry.xcframework" in project_contents
    assert "/* Vendor/Sentry/Sentry.xcframework */ = {isa = PBXFileReference;" in project_contents

    sentry_frameworks_phases = _frameworks_phases_linking_sentry(project_contents)

    assert sentry_frameworks_phases == {"sideBar"}


def _has_swift_package_sentry_path() -> bool:
    project_contents = PBXPROJ.read_text(encoding="utf-8")
    return "sentry-cocoa" in project_contents or "productName = Sentry" in project_contents


def _has_cocoapods_sentry_path() -> bool:
    podfile = IOS_ROOT / "Podfile"
    podfile_lock = IOS_ROOT / "Podfile.lock"
    pods_root = IOS_ROOT / "Pods"
    return (
        _file_contains_pattern(podfile, r"(?im)^\s*pod\s+['\"]Sentry['\"]")
        or _file_contains_pattern(podfile_lock, r"(?m)^\s*-\sSentry\b")
        or any(path.exists() for path in pods_root.rglob("*Sentry*"))
    )


def _has_carthage_sentry_path() -> bool:
    cartfile = IOS_ROOT / "Cartfile"
    cartfile_resolved = IOS_ROOT / "Cartfile.resolved"
    return (
        _file_contains_pattern(cartfile, r"(?i)\bSentry\b")
        or _file_contains_pattern(cartfile_resolved, r"(?i)\bSentry\b")
        or any(path.exists() for path in (IOS_ROOT / "Carthage").rglob("*Sentry*"))
    )


def _has_vendored_sentry_path() -> bool:
    vendor_path = IOS_ROOT / "Vendor" / "Sentry"
    return (vendor_path / "Sentry.xcframework").exists()


def _file_contains_pattern(path: Path, pattern: str) -> bool:
    if path.exists() is False:
        return False
    return re.search(pattern, path.read_text(encoding="utf-8")) is not None


def _frameworks_phases_linking_sentry(project_contents: str) -> set[str]:
    target_names: set[str] = set()
    for phase_match in re.finditer(
        r"(?P<phase_id>[A-F0-9]{24}) /\* Frameworks \*/ = \{\s*isa = PBXFrameworksBuildPhase;.*?files = \((?P<files>.*?)\);\s*runOnlyForDeploymentPostprocessing = 0;\s*\};",
        project_contents,
        re.DOTALL,
    ):
        if "Sentry.xcframework in Frameworks" not in phase_match.group("files"):
            continue
        phase_id = phase_match.group("phase_id")
        for target_name in (
            "sideBar",
            "sideBarWidgetsExtension",
            "ShareExtension",
            "sideBar Safari Extension",
            "sideBar Safari Extension (macOS)",
            "sideBar Safari Extension (macOS) Extension",
        ):
            if phase_id in _native_target_build_phases(project_contents, target_name):
                target_names.add(target_name)
    return target_names


def _native_target_build_phases(project_contents: str, target_name: str) -> str:
    match = re.search(
        rf"[A-F0-9]{{24}} /\* {re.escape(target_name)} \*/ = \{{\s*isa = PBXNativeTarget;.*?buildPhases = \((?P<phases>.*?)\);\s*buildRules = \(",
        project_contents,
        re.DOTALL,
    )
    if match is None:
        return ""
    return match.group("phases")
