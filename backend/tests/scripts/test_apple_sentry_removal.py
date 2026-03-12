"""Repo-level checks guarding the Apple Sentry cleanup."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
PBXPROJ = REPO_ROOT / "ios" / "sideBar" / "sideBar.xcodeproj" / "project.pbxproj"
CI_POST_CLONE_SCRIPT = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "ci_post_clone.sh"
UPLOAD_SCRIPT = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "upload_sentry_dsyms.sh"


def test_project_does_not_reference_sentry_cocoa() -> None:
    project_contents = PBXPROJ.read_text(encoding="utf-8")
    assert "sentry-cocoa" not in project_contents


def test_no_target_depends_on_the_sentry_package_product() -> None:
    project_contents = PBXPROJ.read_text(encoding="utf-8")
    assert "productName = Sentry" not in project_contents


def test_upload_build_phase_is_removed_from_project() -> None:
    project_contents = PBXPROJ.read_text(encoding="utf-8")
    assert "Upload Sentry dSYMs" not in project_contents


def test_ci_post_clone_stops_touching_sentry_cli() -> None:
    script_contents = CI_POST_CLONE_SCRIPT.read_text(encoding="utf-8")
    assert "sentry-cli" not in script_contents


def test_upload_sentry_dsyms_is_disabled_placeholder() -> None:
    script_contents = UPLOAD_SCRIPT.read_text(encoding="utf-8")
    assert "disabled" in script_contents
    assert "exit 0" in script_contents
    assert "sentry-cli" not in script_contents
    assert "debug-files upload" not in script_contents
    assert "SENTRY_AUTH_TOKEN" not in script_contents


def test_bootstrap_no_longer_imports_or_calls_sentry_sdk() -> None:
    bootstrap_contents = (
        REPO_ROOT / "ios" / "sideBar" / "sideBar" / "App" / "SentryBootstrap.swift"
    ).read_text(encoding="utf-8")
    assert "import Sentry" not in bootstrap_contents
    assert "SentrySDK" not in bootstrap_contents


def test_bootstrap_seam_remains_present() -> None:
    bootstrap_contents = (
        REPO_ROOT / "ios" / "sideBar" / "sideBar" / "App" / "SentryBootstrap.swift"
    ).read_text(encoding="utf-8")
    assert "enum SentryBootstrap" in bootstrap_contents
    assert "static func startIfConfigured" in bootstrap_contents
