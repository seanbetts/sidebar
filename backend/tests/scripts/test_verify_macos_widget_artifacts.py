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


def _repo_file_text(relative_path: str) -> str:
    """Return repository file contents for workflow-facing wiring assertions."""
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


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


def test_dev_workflow_wires_debug_verification_only_for_logic_mac() -> None:
    """Dev CI should verify macOS widget artifacts only on the macOS logic lane."""
    workflow = _repo_file_text(".github/workflows/ios-ci.yml")

    assert 'if: ${{ matrix.id == \'logic-mac\' }}' in workflow
    assert '- "scripts/verify_macos_widget_artifacts.py"' in workflow
    assert 'python3 scripts/verify_macos_widget_artifacts.py \\' in workflow
    assert '--mode debug \\' in workflow
    assert '--workspace-root "${{ github.workspace }}" \\' in workflow
    assert '--clean-stale-registrations' in workflow


def test_main_workflow_runs_debug_and_release_widget_verification() -> None:
    """Main CI should run dedicated macOS Debug and Release widget verification."""
    workflow = _repo_file_text(".github/workflows/ios-ci-main.yml")

    assert "ios_widget_verification_main:" in workflow
    assert 'needs: [ios_prepare_packages, ios_widget_verification_main]' in workflow
    assert "- mode: debug" in workflow
    assert '- mode: release' in workflow
    assert '--mode "${{ matrix.mode }}" \\' in workflow
    assert '--clean-stale-registrations' in workflow
    assert 'platform=iOS Simulator,name=iPhone 17 Pro' in workflow
    assert 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' in workflow


def test_manual_dispatch_wires_debug_and_release_widget_verification_by_lane() -> None:
    """Manual CI should gate widget verification by lane without changing simulator lanes."""
    workflow = _repo_file_text(".github/workflows/ios-ci-dispatch.yml")

    assert "ios_widget_verification_dispatch:" in workflow
    assert 'lanes: "all logic"' in workflow
    assert 'lanes: "all surface ui extensions"' in workflow
    assert "contains(matrix.lanes, github.event.inputs.lane)" in workflow
    assert '--mode "${{ matrix.mode }}" \\' in workflow
    assert '--clean-stale-registrations' in workflow


def test_release_main_uses_archive_export_verifier_with_shared_script() -> None:
    """Release promotion should block on archive/export widget verification via the shared script."""
    release_script = _repo_file_text("scripts/release-main.sh")

    assert "--export-options-plist <path>" in release_script
    assert 'default_export_options_plist="ios/sideBar/ExportOptions.plist"' in release_script
    assert "python3 scripts/verify_macos_widget_artifacts.py \\" in release_script
    assert "--mode archive-export \\" in release_script
    assert '--workspace-root "$PWD" \\' in release_script
    assert '--export-options-plist "$export_options_plist" \\' in release_script
    assert "--clean-stale-registrations" in release_script


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
