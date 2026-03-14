"""Tests for scripts/verify_macos_widget_artifacts.py."""

from __future__ import annotations

import importlib.util
import plistlib
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

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


def _load_workflow(relative_path: str) -> dict:
    """Return parsed workflow YAML for structure-aware assertions."""
    return yaml.safe_load(_repo_file_text(relative_path))


def _job_step_by_name(*, job: dict, name: str) -> dict:
    """Return one step by display name."""
    matches = [step for step in job["steps"] if step.get("name") == name]
    assert len(matches) == 1
    return matches[0]


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
    workflow = _load_workflow(".github/workflows/ios-ci.yml")
    jobs = workflow["jobs"]

    ios_test_dev = jobs["ios_test_dev"]
    assert ios_test_dev["needs"] == ["ios_quality", "ios_prepare_packages"]
    assert {
        lane["id"] for lane in ios_test_dev["strategy"]["matrix"]["include"]
    } == {"logic-iphone", "logic-ipad", "logic-mac"}

    verify_step = _job_step_by_name(job=ios_test_dev, name="Verify macOS widget artifacts (Debug)")
    assert verify_step["if"] == "${{ matrix.id == 'logic-mac' }}"
    assert verify_step["run"] == (
        "python3 scripts/verify_macos_widget_artifacts.py \\\n"
        "  --mode debug \\\n"
        "  --workspace-root \"${{ github.workspace }}\" \\\n"
        "  --clean-stale-registrations\n"
    )


def test_main_workflow_runs_debug_and_release_widget_verification() -> None:
    """Main CI should run dedicated macOS Debug and Release widget verification."""
    workflow = _load_workflow(".github/workflows/ios-ci-main.yml")
    jobs = workflow["jobs"]

    widget_job = jobs["ios_widget_verification_main"]
    assert widget_job["needs"] == ["ios_prepare_packages"]
    assert [row["mode"] for row in widget_job["strategy"]["matrix"]["include"]] == [
        "debug",
        "release",
    ]
    verify_step = _job_step_by_name(
        job=widget_job,
        name="Verify macOS widget artifacts (${{ matrix.label }})",
    )
    assert verify_step["run"] == (
        "python3 scripts/verify_macos_widget_artifacts.py \\\n"
        "  --mode \"${{ matrix.mode }}\" \\\n"
        "  --workspace-root \"${{ github.workspace }}\" \\\n"
        "  --clean-stale-registrations\n"
    )

    ios_test_main = jobs["ios_test_main"]
    assert ios_test_main["needs"] == ["ios_prepare_packages", "ios_widget_verification_main"]
    assert {
        lane["id"] for lane in ios_test_main["strategy"]["matrix"]["include"]
    } == {"surface", "ui", "extensions"}


def test_manual_dispatch_wires_debug_and_release_widget_verification_by_lane() -> None:
    """Manual CI should gate widget verification by lane without changing simulator lanes."""
    workflow = _load_workflow(".github/workflows/ios-ci-dispatch.yml")
    jobs = workflow["jobs"]

    widget_job = jobs["ios_widget_verification_dispatch"]
    assert widget_job["needs"] == ["ios_prepare_packages"]
    assert widget_job["strategy"]["matrix"]["include"] == [
        {
            "mode": "debug",
            "label": "macOS Debug widget verification",
            "lanes_json": '["all", "logic"]',
        },
        {
            "mode": "release",
            "label": "macOS Release widget verification",
            "lanes_json": '["all", "surface", "ui", "extensions"]',
        },
    ]
    checkout_step = _job_step_by_name(job=widget_job, name="Checkout")
    verify_step = _job_step_by_name(
        job=widget_job,
        name="Verify macOS widget artifacts (${{ matrix.label }})",
    )
    expected_if = "${{ contains(fromJSON(matrix.lanes_json), github.event.inputs.lane) }}"
    assert checkout_step["if"] == expected_if
    assert verify_step["if"] == expected_if
    assert verify_step["run"] == (
        "python3 scripts/verify_macos_widget_artifacts.py \\\n"
        "  --mode \"${{ matrix.mode }}\" \\\n"
        "  --workspace-root \"${{ github.workspace }}\" \\\n"
        "  --clean-stale-registrations\n"
    )

    ios_test_dispatch = jobs["ios_test_dispatch"]
    assert ios_test_dispatch["needs"] == ["ios_prepare_packages", "ios_widget_verification_dispatch"]
    assert {
        lane["id"] for lane in ios_test_dispatch["strategy"]["matrix"]["include"]
    } == {"logic-iphone", "logic-ipad", "logic-mac", "surface", "ui", "extensions"}


def test_release_main_uses_archive_export_verifier_with_shared_script() -> None:
    """Release promotion should block on archive/export widget verification via the shared script."""
    release_script = _repo_file_text("scripts/release-main.sh")

    assert "--export-options-plist <path>" in release_script
    assert 'default_export_options_plist="$repo_root/ios/sideBar/ExportOptions.plist"' in release_script
    assert 'repo_root="$(git rev-parse --show-toplevel)"' in release_script
    assert 'python3 "$repo_root/scripts/verify_macos_widget_artifacts.py" \\' in release_script
    assert "--mode archive-export \\" in release_script
    assert '--workspace-root "$repo_root" \\' in release_script
    assert '--workspace-root "$PWD" \\' not in release_script
    assert '--export-options-plist "$export_options_plist" \\' in release_script
    assert "--clean-stale-registrations" in release_script


def test_default_export_options_plist_exists_for_release_archive_export() -> None:
    """Release flows should have a checked-in macOS export-options plist at the default path."""
    export_options_path = REPO_ROOT / "ios/sideBar/ExportOptions.plist"

    assert export_options_path.is_file()

    with export_options_path.open("rb") as handle:
        export_options = plistlib.load(handle)

    assert export_options == {
        "destination": "export",
        "method": "mac-application",
        "signingStyle": "automatic",
        "teamID": "YOURTEAMID",
    }


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
