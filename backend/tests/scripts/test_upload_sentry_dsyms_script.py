"""Tests for the Apple dSYM upload seam."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "upload_sentry_dsyms.sh"


def test_upload_script_skips_non_release_builds(tmp_path: Path) -> None:
    """Non-Release Apple builds should skip dSYM upload cleanly."""
    env = base_env(tmp_path)
    env["CONFIGURATION"] = "Debug"

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "skipping upload for non-Release configuration 'Debug'" in result.stdout


def test_upload_script_skips_simulator_builds(tmp_path: Path) -> None:
    """Simulator Apple builds should skip dSYM upload cleanly."""
    env = base_env(tmp_path)
    env["PLATFORM_NAME"] = "iphonesimulator"

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "skipping upload for simulator build" in result.stdout


def test_upload_script_fails_when_cli_is_missing_and_upload_is_enabled(tmp_path: Path) -> None:
    """Release device builds should fail loudly when upload is enabled but sentry-cli is absent."""
    env = base_env(tmp_path)
    env["PATH"] = "/usr/bin:/bin"
    (tmp_path / "dSYMs" / "sideBar.app.dSYM").mkdir(parents=True)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "sentry-cli is required" in result.stdout


def test_upload_script_uses_explicit_sentry_cli_path(tmp_path: Path) -> None:
    """Release device builds should upload through sentry-cli when an explicit path is provided."""
    env = os.environ.copy()
    env.update(
        {
            "CONFIGURATION": "Release",
            "PLATFORM_NAME": "iphoneos",
            "DWARF_DSYM_FOLDER_PATH": str(tmp_path / "dSYMs"),
            "DWARF_DSYM_FILE_NAME": "sideBar.app.dSYM",
            "PRODUCT_BUNDLE_IDENTIFIER": "ai.sidebar.sidebar",
            "SENTRY_AUTH_TOKEN": "token",
            "SENTRY_ORG": "sidebar",
            "SENTRY_PROJECT": "apple",
        }
    )
    dsym_dir = tmp_path / "dSYMs"
    (dsym_dir / "sideBar.app.dSYM").mkdir(parents=True)
    cli_path = tmp_path / "sentry-cli"
    cli_path.write_text(
        "#!/bin/bash\n"
        "echo \"$@\" > \"$TMPDIR/sentry-cli-args.txt\"\n",
        encoding="utf-8",
    )
    cli_path.chmod(0o755)
    env["SENTRY_CLI_PATH"] = str(cli_path)
    env["TMPDIR"] = str(tmp_path)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "uploading sideBar.app.dSYM for ai.sidebar.sidebar" in result.stdout
    assert "upload complete" in result.stdout
    assert "token" not in result.stdout
    assert "apple" not in result.stdout
    args = (tmp_path / "sentry-cli-args.txt").read_text(encoding="utf-8")
    assert "debug-files upload" in args
    assert "--org sidebar" in args
    assert "--project apple" in args
    assert "--no-progress" in args
    assert str(dsym_dir / "sideBar.app.dSYM") in args


def test_upload_script_uses_explicit_dsym_override_path(tmp_path: Path) -> None:
    """Archive upload hooks should be able to provide an explicit dSYM path override."""
    env = os.environ.copy()
    env.update(
        {
            "CONFIGURATION": "Release",
            "PLATFORM_NAME": "iphoneos",
            "PRODUCT_BUNDLE_IDENTIFIER": "ai.sidebar.sidebar",
            "SENTRY_AUTH_TOKEN": "token",
            "SENTRY_ORG": "sidebar",
            "SENTRY_PROJECT": "apple",
        }
    )
    archive_dsym = tmp_path / "build.xcarchive" / "dSYMs" / "sideBar.app.dSYM"
    archive_dsym.mkdir(parents=True)
    cli_path = tmp_path / "sentry-cli"
    cli_path.write_text(
        "#!/bin/bash\n"
        "echo \"$@\" > \"$TMPDIR/sentry-cli-args.txt\"\n",
        encoding="utf-8",
    )
    cli_path.chmod(0o755)
    env["SENTRY_CLI_PATH"] = str(cli_path)
    env["SENTRY_DSYM_PATH"] = str(archive_dsym)
    env["TMPDIR"] = str(tmp_path)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "uploading sideBar.app.dSYM for ai.sidebar.sidebar" in result.stdout
    args = (tmp_path / "sentry-cli-args.txt").read_text(encoding="utf-8")
    assert str(archive_dsym) in args


def base_env(tmp_path: Path) -> dict[str, str]:
    """Construct the baseline environment for the upload hook."""
    env = os.environ.copy()
    env.update(
        {
            "CONFIGURATION": "Release",
            "PLATFORM_NAME": "iphoneos",
            "DWARF_DSYM_FOLDER_PATH": str(tmp_path / "dSYMs"),
            "DWARF_DSYM_FILE_NAME": "sideBar.app.dSYM",
            "PRODUCT_BUNDLE_IDENTIFIER": "ai.sidebar.sidebar",
            "SENTRY_AUTH_TOKEN": "token",
            "SENTRY_ORG": "sidebar",
            "SENTRY_PROJECT": "apple",
        }
    )
    return env
