"""Tests for ios/sideBar/ci_scripts/upload_sentry_dsyms.sh."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "upload_sentry_dsyms.sh"


def test_upload_script_is_explicit_disabled_placeholder(tmp_path: Path) -> None:
    """The legacy Apple upload hook should exit cleanly and say it is disabled."""
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

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "disabled pending future reintroduction" in result.stdout
    assert "Please re-enable this script once a new Apple dSYM upload workflow is defined." in (
        result.stdout
    )
