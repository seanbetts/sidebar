"""Tests for ios/sideBar/ci_scripts/upload_sentry_dsyms.sh."""

from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "upload_sentry_dsyms.sh"


def write_executable(path: Path, contents: str) -> None:
    """Create an executable helper script."""
    path.write_text(contents, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def base_env(tmp_path: Path) -> dict[str, str]:
    """Construct the minimal Xcode build environment for the upload script."""
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
    (tmp_path / "dSYMs" / "sideBar.app.dSYM").mkdir(parents=True)
    return env


def test_upload_script_skips_non_release_builds(tmp_path: Path) -> None:
    """Debug builds should not attempt to upload dSYMs."""
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
    assert "non-Release configuration" in result.stdout


def test_upload_script_fails_when_cli_missing(tmp_path: Path) -> None:
    """Configured uploads should fail fast when sentry-cli is unavailable."""
    env = base_env(tmp_path)
    env["PATH"] = "/usr/bin:/bin"

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


def test_upload_script_uses_repo_local_cli(tmp_path: Path) -> None:
    """The uploader should prefer the repo-local CLI installed by ci_post_clone.sh."""
    env = base_env(tmp_path)
    sentry_cli_dir = REPO_ROOT / "ios" / "sideBar" / ".tools" / "sentry-cli" / "bin"
    sentry_cli_dir.mkdir(parents=True, exist_ok=True)
    log_path = tmp_path / "sentry-cli.log"
    write_executable(
        sentry_cli_dir / "sentry-cli",
        "#!/bin/bash\nprintf '%s\\n' \"$*\" > \"$TEST_SENTRY_CLI_LOG\"\n",
    )
    env["TEST_SENTRY_CLI_LOG"] = str(log_path)
    env["PATH"] = "/usr/bin:/bin"

    try:
        result = subprocess.run(
            [str(SCRIPT_PATH)],
            cwd=REPO_ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        (sentry_cli_dir / "sentry-cli").unlink(missing_ok=True)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "--org sidebar --project apple --no-progress" in log_path.read_text(encoding="utf-8")
    assert str(tmp_path / "dSYMs" / "sideBar.app.dSYM") in log_path.read_text(encoding="utf-8")
