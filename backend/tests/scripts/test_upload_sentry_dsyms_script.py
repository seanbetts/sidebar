"""Tests for the Apple dSYM upload seam."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "upload_sentry_dsyms.sh"


def test_upload_script_remains_explicit_and_testable(tmp_path: Path) -> None:
    """The Apple upload hook should stay visible and produce a stable status message."""
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
    script_contents = SCRIPT_PATH.read_text(encoding="utf-8")

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert "#!/bin/bash" in script_contents
    assert "set -euo pipefail" in script_contents
    assert "sentry-dsym-upload:" in script_contents
    assert result.returncode == 0
    assert "sentry-dsym-upload:" in result.stdout
    assert "token" not in result.stdout
    assert "sidebar" not in result.stdout
    assert "apple" not in result.stdout
    assert result.stdout.strip()
