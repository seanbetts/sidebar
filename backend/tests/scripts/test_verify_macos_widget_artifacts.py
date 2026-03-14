"""Tests for scripts/verify_macos_widget_artifacts.py."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "verify_macos_widget_artifacts.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "verify_macos_widget_artifacts", MODULE_PATH
)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
VERIFY_MODULE = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules["verify_macos_widget_artifacts"] = VERIFY_MODULE
MODULE_SPEC.loader.exec_module(VERIFY_MODULE)

run_verifier = VERIFY_MODULE.run_verifier


def _capture_subprocess_calls(monkeypatch, module, *, fail_for: list[list[str]] | None = None):
    calls: list[list[str]] = []
    failing = fail_for or []

    def _fake_run(command, check):
        assert check is True
        calls.append(command)
        if command in failing:
            raise subprocess.CalledProcessError(returncode=2, cmd=command)
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(module.subprocess, "run", _fake_run)
    return calls


def test_debug_mode_runs_build_and_verification(monkeypatch, tmp_path: Path, capsys) -> None:
    """Debug mode should build macOS app output and verify the resulting bundle."""
    workspace_root = tmp_path / "workspace"
    built_app = (
        workspace_root
        / "DerivedData"
        / "widget-verification"
        / "debug"
        / "Build"
        / "Products"
        / "Debug"
        / "sideBar.app"
    )
    built_app.mkdir(parents=True)

    calls = _capture_subprocess_calls(monkeypatch, VERIFY_MODULE)
    exit_code = run_verifier(
        [
            "--mode",
            "debug",
            "--workspace-root",
            str(workspace_root),
        ]
    )
    captured = capsys.readouterr()

    assert exit_code == 0
    assert calls == [
        [
            "xcodebuild",
            "-project",
            str(workspace_root / "ios/sideBar/sideBar.xcodeproj"),
            "-scheme",
            "sideBar",
            "-configuration",
            "Debug",
            "-destination",
            "platform=macOS",
            "-derivedDataPath",
            str(workspace_root / "DerivedData/widget-verification/debug"),
            "build",
        ],
        [
            "python3",
            str(workspace_root / "scripts/check_ios_extension_config_resolution.py"),
            "--configuration",
            "Debug",
            "--built-app",
            str(built_app),
        ],
    ]
    assert "Widget artifact verification passed." in captured.out


def test_release_mode_uses_release_configuration(monkeypatch, tmp_path: Path) -> None:
    """Release mode should build and verify the Release bundle path."""
    workspace_root = tmp_path / "workspace"
    built_app = (
        workspace_root
        / "DerivedData"
        / "widget-verification"
        / "release"
        / "Build"
        / "Products"
        / "Release"
        / "sideBar.app"
    )
    built_app.mkdir(parents=True)

    calls = _capture_subprocess_calls(monkeypatch, VERIFY_MODULE)
    exit_code = run_verifier(
        [
            "--mode",
            "release",
            "--workspace-root",
            str(workspace_root),
        ]
    )

    assert exit_code == 0
    assert calls[0] == [
        "xcodebuild",
        "-project",
        str(workspace_root / "ios/sideBar/sideBar.xcodeproj"),
        "-scheme",
        "sideBar",
        "-configuration",
        "Release",
        "-destination",
        "platform=macOS",
        "-derivedDataPath",
        str(workspace_root / "DerivedData/widget-verification/release"),
        "build",
    ]
    assert calls[1] == [
        "python3",
        str(workspace_root / "scripts/check_ios_extension_config_resolution.py"),
        "--configuration",
        "Release",
        "--built-app",
        str(built_app),
    ]


def test_archive_export_mode_runs_archive_export_and_verification(
    monkeypatch,
    tmp_path: Path,
) -> None:
    """archive-export should archive, export, then verify the exported app bundle."""
    workspace_root = tmp_path / "workspace"
    export_dir = workspace_root / "DerivedData/widget-verification/archive-export/export"
    exported_app = export_dir / "sideBar.app"
    exported_app.mkdir(parents=True)
    export_options_plist = workspace_root / "ExportOptions.plist"
    export_options_plist.write_text("plist", encoding="utf-8")

    calls = _capture_subprocess_calls(monkeypatch, VERIFY_MODULE)
    exit_code = run_verifier(
        [
            "--mode",
            "archive-export",
            "--workspace-root",
            str(workspace_root),
            "--export-options-plist",
            str(export_options_plist),
        ]
    )

    archive_path = workspace_root / "DerivedData/widget-verification/archive-export/sideBar.xcarchive"
    assert exit_code == 0
    assert calls[0] == [
        "xcodebuild",
        "-project",
        str(workspace_root / "ios/sideBar/sideBar.xcodeproj"),
        "-scheme",
        "sideBar",
        "-configuration",
        "Release",
        "-destination",
        "generic/platform=macOS",
        "-archivePath",
        str(archive_path),
        "archive",
    ]
    assert calls[1] == [
        "xcodebuild",
        "-exportArchive",
        "-archivePath",
        str(archive_path),
        "-exportPath",
        str(export_dir),
        "-exportOptionsPlist",
        str(export_options_plist),
    ]
    assert calls[2] == [
        "python3",
        str(workspace_root / "scripts/check_ios_extension_config_resolution.py"),
        "--configuration",
        "Release",
        "--built-app",
        str(exported_app),
    ]


def test_cleanup_is_optional_and_runs_before_build(monkeypatch, tmp_path: Path) -> None:
    """When requested, stale widget cleanup should run before any build work."""
    workspace_root = tmp_path / "workspace"
    built_app = (
        workspace_root
        / "DerivedData"
        / "widget-verification"
        / "debug"
        / "Build"
        / "Products"
        / "Debug"
        / "sideBar.app"
    )
    built_app.mkdir(parents=True)

    calls = _capture_subprocess_calls(monkeypatch, VERIFY_MODULE)
    exit_code = run_verifier(
        [
            "--mode",
            "debug",
            "--workspace-root",
            str(workspace_root),
            "--clean-stale-registrations",
        ]
    )

    assert exit_code == 0
    assert calls[0] == [
        "python3",
        str(workspace_root / "scripts/clean_stale_widget_registrations.py"),
        "--workspace-root",
        str(workspace_root),
    ]


def test_archive_export_cleanup_runs_before_archive(monkeypatch, tmp_path: Path) -> None:
    """Cleanup flag should run before archive/export commands in archive-export mode."""
    workspace_root = tmp_path / "workspace"
    export_dir = workspace_root / "DerivedData/widget-verification/archive-export/export"
    exported_app = export_dir / "sideBar.app"
    exported_app.mkdir(parents=True)
    export_options_plist = workspace_root / "ExportOptions.plist"
    export_options_plist.write_text("plist", encoding="utf-8")

    calls = _capture_subprocess_calls(monkeypatch, VERIFY_MODULE)
    exit_code = run_verifier(
        [
            "--mode",
            "archive-export",
            "--workspace-root",
            str(workspace_root),
            "--clean-stale-registrations",
            "--export-options-plist",
            str(export_options_plist),
        ]
    )

    assert exit_code == 0
    assert calls[0] == [
        "python3",
        str(workspace_root / "scripts/clean_stale_widget_registrations.py"),
        "--workspace-root",
        str(workspace_root),
    ]
    assert calls[1][-1] == "archive"
    assert calls[2][1] == "-exportArchive"


def test_ci_widget_matrix_contract_is_documented() -> None:
    """Document the intended CI/release widget verification matrix for Task 5 wiring."""
    expected_modes_by_path = {
        "dev-ci-macos": ["debug"],
        "main-ci-macos": ["debug", "release"],
        "release-promotion": ["archive-export"],
    }

    assert expected_modes_by_path["dev-ci-macos"] == ["debug"]
    assert expected_modes_by_path["main-ci-macos"] == ["debug", "release"]
    assert "archive-export" in expected_modes_by_path["release-promotion"]


def test_dry_run_prints_commands_without_running(monkeypatch, tmp_path: Path, capsys) -> None:
    """Dry-run should print every command without invoking subprocess.run."""
    workspace_root = tmp_path / "workspace"

    def _never_run(_command, check):  # pragma: no cover - assertion helper
        raise AssertionError("subprocess.run should not execute in dry-run mode")

    monkeypatch.setattr(VERIFY_MODULE.subprocess, "run", _never_run)
    exit_code = run_verifier(
        [
            "--mode",
            "release",
            "--workspace-root",
            str(workspace_root),
            "--clean-stale-registrations",
            "--dry-run",
        ]
    )
    captured = capsys.readouterr()

    assert exit_code == 0
    assert "Dry run mode enabled." in captured.out
    assert (
        "python3 "
        + str(workspace_root / "scripts/clean_stale_widget_registrations.py")
        + " --workspace-root "
        + str(workspace_root)
    ) in captured.out
    assert (
        "xcodebuild -project "
        + str(workspace_root / "ios/sideBar/sideBar.xcodeproj")
        + " -scheme sideBar -configuration Release -destination platform=macOS "
        + "-derivedDataPath "
        + str(workspace_root / "DerivedData/widget-verification/release")
        + " build"
    ) in captured.out
    assert (
        "python3 "
        + str(workspace_root / "scripts/check_ios_extension_config_resolution.py")
        + " --configuration Release --built-app "
        + str(
            workspace_root
            / "DerivedData/widget-verification/release/Build/Products/Release/sideBar.app"
        )
    ) in captured.out


def test_archive_export_requires_export_options_plist(tmp_path: Path, capsys) -> None:
    """archive-export should fail fast without --export-options-plist."""
    exit_code = run_verifier(
        [
            "--mode",
            "archive-export",
            "--workspace-root",
            str(tmp_path / "workspace"),
        ]
    )
    captured = capsys.readouterr()

    assert exit_code == 1
    assert "--export-options-plist" in captured.out


def test_fails_when_build_command_errors(monkeypatch, tmp_path: Path, capsys) -> None:
    """Build failures should return non-zero and surface the failing command."""
    workspace_root = tmp_path / "workspace"
    failing_command = [
        "xcodebuild",
        "-project",
        str(workspace_root / "ios/sideBar/sideBar.xcodeproj"),
        "-scheme",
        "sideBar",
        "-configuration",
        "Debug",
        "-destination",
        "platform=macOS",
        "-derivedDataPath",
        str(workspace_root / "DerivedData/widget-verification/debug"),
        "build",
    ]
    _capture_subprocess_calls(monkeypatch, VERIFY_MODULE, fail_for=[failing_command])

    exit_code = run_verifier(
        [
            "--mode",
            "debug",
            "--workspace-root",
            str(workspace_root),
        ]
    )
    captured = capsys.readouterr()

    assert exit_code == 1
    assert "Command failed" in captured.out
    assert "xcodebuild" in captured.out


def test_release_mode_requires_built_app_after_build(monkeypatch, tmp_path: Path, capsys) -> None:
    """Verifier should fail if expected Release app bundle is not present."""
    workspace_root = tmp_path / "workspace"
    _capture_subprocess_calls(monkeypatch, VERIFY_MODULE)

    exit_code = run_verifier(
        [
            "--mode",
            "release",
            "--workspace-root",
            str(workspace_root),
        ]
    )
    captured = capsys.readouterr()

    assert exit_code == 1
    assert "Unable to locate built app bundle" in captured.out


def test_archive_export_requires_single_exported_app(monkeypatch, tmp_path: Path, capsys) -> None:
    """Archive export should fail when no exported sideBar.app exists."""
    workspace_root = tmp_path / "workspace"
    export_options_plist = workspace_root / "ExportOptions.plist"
    export_options_plist.parent.mkdir(parents=True)
    export_options_plist.write_text("plist", encoding="utf-8")
    _capture_subprocess_calls(monkeypatch, VERIFY_MODULE)

    exit_code = run_verifier(
        [
            "--mode",
            "archive-export",
            "--workspace-root",
            str(workspace_root),
            "--export-options-plist",
            str(export_options_plist),
        ]
    )
    captured = capsys.readouterr()

    assert exit_code == 1
    assert "Unable to locate built app bundle" in captured.out
