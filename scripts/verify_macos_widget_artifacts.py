#!/usr/bin/env python3
"""Build and verify macOS widget artifacts for debug, release, or archive/export flows."""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

APP_NAME = "sideBar.app"
XCODE_PROJECT_RELATIVE_PATH = Path("ios/sideBar/sideBar.xcodeproj")
BUILD_SCHEME = "sideBar"
DERIVED_DATA_BASE = Path("DerivedData/widget-verification")
WIDGET_BUNDLE_ID = "ai.sidebar.sidebar.sideBarWidgets"


def emit(message: str = "") -> None:
    """Write one line to stdout."""
    sys.stdout.write(f"{message}\n")


def shell_join(command: Sequence[str]) -> str:
    """Return a shell-safe string for one command."""
    return shlex.join(command)


@dataclass(frozen=True)
class CommandPlan:
    """Mode-specific command contract and artifact locations."""

    pre_verification_commands: list[list[str]]
    configuration: str
    expected_app_path: Path
    archive_export_output_dir: Path | None = None


def mode_output_root(*, workspace_root: Path, mode: str) -> Path:
    """Return the mode-specific output root directory."""
    return workspace_root / DERIVED_DATA_BASE / mode


def build_command_plan(
    *,
    mode: str,
    workspace_root: Path,
    python_executable: str,
    export_options_plist: Path | None,
    clean_stale_registrations: bool,
) -> CommandPlan:
    """Return the centralized command plan for the requested mode."""
    project_path = workspace_root / XCODE_PROJECT_RELATIVE_PATH
    commands: list[list[str]] = []

    if clean_stale_registrations:
        commands.append(
            [
                python_executable,
                str(workspace_root / "scripts/clean_stale_widget_registrations.py"),
                "--workspace-root",
                str(workspace_root),
                "--bundle-id",
                WIDGET_BUNDLE_ID,
            ]
        )

    if mode == "debug":
        derived_data_path = mode_output_root(workspace_root=workspace_root, mode="debug")
        commands.append(
            [
                "xcodebuild",
                "-project",
                str(project_path),
                "-scheme",
                BUILD_SCHEME,
                "-configuration",
                "Debug",
                "-destination",
                "platform=macOS",
                "-derivedDataPath",
                str(derived_data_path),
                "build",
            ]
        )
        return CommandPlan(
            pre_verification_commands=commands,
            configuration="Debug",
            expected_app_path=derived_data_path / "Build/Products/Debug" / APP_NAME,
        )

    if mode == "release":
        derived_data_path = mode_output_root(workspace_root=workspace_root, mode="release")
        commands.append(
            [
                "xcodebuild",
                "-project",
                str(project_path),
                "-scheme",
                BUILD_SCHEME,
                "-configuration",
                "Release",
                "-destination",
                "platform=macOS",
                "-derivedDataPath",
                str(derived_data_path),
                "build",
            ]
        )
        return CommandPlan(
            pre_verification_commands=commands,
            configuration="Release",
            expected_app_path=derived_data_path / "Build/Products/Release" / APP_NAME,
        )

    if export_options_plist is None:
        raise ValueError("archive-export mode requires --export-options-plist")

    archive_export_root = mode_output_root(workspace_root=workspace_root, mode="archive-export")
    archive_path = archive_export_root / "sideBar.xcarchive"
    export_path = archive_export_root / "export"
    commands.extend(
        [
            [
                "xcodebuild",
                "-project",
                str(project_path),
                "-scheme",
                BUILD_SCHEME,
                "-configuration",
                "Release",
                "-destination",
                "generic/platform=macOS",
                "-archivePath",
                str(archive_path),
                "archive",
            ],
            [
                "xcodebuild",
                "-exportArchive",
                "-archivePath",
                str(archive_path),
                "-exportPath",
                str(export_path),
                "-exportOptionsPlist",
                str(export_options_plist),
            ],
        ]
    )
    return CommandPlan(
        pre_verification_commands=commands,
        configuration="Release",
        expected_app_path=export_path / APP_NAME,
        archive_export_output_dir=export_path,
    )


def verification_command(
    *,
    workspace_root: Path,
    python_executable: str,
    configuration: str,
    app_path: Path,
) -> list[str]:
    """Return the final widget artifact verification command."""
    return [
        python_executable,
        str(workspace_root / "scripts/check_ios_extension_config_resolution.py"),
        "--configuration",
        configuration,
        "--built-app",
        str(app_path),
    ]


def locate_built_app_bundle(*, plan: CommandPlan, mode: str) -> Path:
    """Locate the app bundle produced by the current mode."""
    if mode in {"debug", "release"}:
        if plan.expected_app_path.exists():
            return plan.expected_app_path
        raise FileNotFoundError(
            f"Unable to locate built app bundle at expected path: {plan.expected_app_path}"
        )

    assert plan.archive_export_output_dir is not None
    candidates = sorted(
        path
        for path in plan.archive_export_output_dir.rglob(APP_NAME)
        if path.name == APP_NAME and path.is_dir()
    )
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise FileNotFoundError(
            "Unable to locate built app bundle in archive export output: "
            f"{plan.archive_export_output_dir}"
        )
    raise FileNotFoundError(
        "Unable to locate built app bundle, multiple candidates found: "
        + ", ".join(str(path) for path in candidates)
    )


def execute_commands(commands: Sequence[Sequence[str]]) -> None:
    """Run command list in order, raising on first failure."""
    for command in commands:
        subprocess.run(list(command), check=True)


def run_verifier(argv: list[str] | None = None) -> int:
    """CLI entrypoint used by tests and script execution."""
    parser = argparse.ArgumentParser(
        description=(
            "Build and verify macOS widget artifacts by orchestrating xcodebuild and "
            "the extension config-resolution checker."
        )
    )
    parser.add_argument(
        "--mode",
        choices=("debug", "release", "archive-export"),
        required=True,
        help="Verification mode to execute.",
    )
    parser.add_argument(
        "--workspace-root",
        type=Path,
        required=True,
        help="Absolute path to the sideBar workspace root.",
    )
    parser.add_argument(
        "--export-options-plist",
        type=Path,
        help="Required for archive-export mode.",
    )
    parser.add_argument(
        "--clean-stale-registrations",
        action="store_true",
        help="Run stale widget registration cleanup before build/archive steps.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without running them.",
    )
    parser.add_argument(
        "--python-executable",
        default="python3",
        help="Python executable used when invoking helper scripts.",
    )
    args = parser.parse_args(argv)

    workspace_root = args.workspace_root.resolve()
    try:
        plan = build_command_plan(
            mode=args.mode,
            workspace_root=workspace_root,
            python_executable=args.python_executable,
            export_options_plist=args.export_options_plist,
            clean_stale_registrations=args.clean_stale_registrations,
        )
    except ValueError as exc:
        emit(str(exc))
        return 1

    if args.dry_run:
        emit("Dry run mode enabled.")
        for command in plan.pre_verification_commands:
            emit(shell_join(command))
        emit(
            shell_join(
                verification_command(
                    workspace_root=workspace_root,
                    python_executable=args.python_executable,
                    configuration=plan.configuration,
                    app_path=plan.expected_app_path,
                )
            )
        )
        return 0

    try:
        execute_commands(plan.pre_verification_commands)
        built_app_path = locate_built_app_bundle(plan=plan, mode=args.mode)
        execute_commands(
            [
                verification_command(
                    workspace_root=workspace_root,
                    python_executable=args.python_executable,
                    configuration=plan.configuration,
                    app_path=built_app_path,
                )
            ]
        )
    except subprocess.CalledProcessError as exc:
        emit(f"Command failed with exit {exc.returncode}: {shell_join(exc.cmd)}")
        return 1
    except FileNotFoundError as exc:
        emit(str(exc))
        return 1

    emit("Widget artifact verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(run_verifier())
