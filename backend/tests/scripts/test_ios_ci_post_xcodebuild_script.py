"""Tests for ios/sideBar/ci_scripts/ci_post_xcodebuild.sh."""

from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "ci_post_xcodebuild.sh"


def write_executable(path: Path, contents: str) -> None:
    """Create an executable helper script."""
    path.write_text(contents, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def test_ci_post_xcodebuild_uploads_archive_dsym_via_upload_hook(tmp_path: Path) -> None:
    """Xcode Cloud post-xcodebuild should upload the archived app dSYM."""
    archive_path = tmp_path / "build.xcarchive"
    dsym_path = archive_path / "dSYMs" / "sideBar.app.dSYM"
    dsym_path.mkdir(parents=True)
    upload_log = tmp_path / "upload-log.txt"
    cli_path = tmp_path / "sentry-cli"
    write_executable(
        cli_path,
        "#!/bin/bash\n"
        "echo \"$@\" > \"$TMPDIR/sentry-cli-args.txt\"\n",
    )
    env = os.environ.copy()
    env.update(
        {
            "TMPDIR": str(tmp_path),
            "CI_ARCHIVE_PATH": str(archive_path),
            "SENTRY_AUTH_TOKEN": "token",
            "SENTRY_ORG": "sidebar",
            "SENTRY_PROJECT": "apple",
            "SENTRY_CLI_PATH": str(cli_path),
        }
    )

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "uploading archived dSYM" in result.stdout
    args = (tmp_path / "sentry-cli-args.txt").read_text(encoding="utf-8")
    assert str(dsym_path) in args


def test_ci_post_xcodebuild_skips_when_archive_is_missing(tmp_path: Path) -> None:
    """Xcode Cloud post-xcodebuild should skip cleanly when no archive is present."""
    env = os.environ.copy()
    env.update(
        {
            "CI_ARCHIVE_PATH": str(tmp_path / "missing.xcarchive"),
            "SENTRY_AUTH_TOKEN": "token",
            "SENTRY_ORG": "sidebar",
            "SENTRY_PROJECT": "apple",
        }
    )

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "skipping upload because archive path does not exist" in result.stdout
