"""Tests for ios/sideBar/ci_scripts/ci_post_clone.sh."""

from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "ios" / "sideBar" / "ci_scripts" / "ci_post_clone.sh"


def write_executable(path: Path, contents: str) -> None:
    """Create an executable helper script."""
    path.write_text(contents, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def make_temp_repo(tmp_path: Path) -> Path:
    """Build the minimal Xcode Cloud directory structure the script expects."""
    repo_root = tmp_path / "repo"
    config_dir = repo_root / "ios" / "sideBar" / "Config"
    config_dir.mkdir(parents=True)
    return repo_root


def required_env(repo_root: Path, bin_dir: Path) -> dict[str, str]:
    """Construct the baseline environment required by ci_post_clone.sh."""
    env = os.environ.copy()
    env.update(
        {
            "CI_PRIMARY_REPOSITORY_PATH": str(repo_root),
            "PATH": f"{bin_dir}:{env['PATH']}",
            "API_BASE_URL": "https://api.sidebar.example/api/v1",
            "SUPABASE_URL": "https://sidebar.supabase.co",
            "SUPABASE_ANON_KEY": "anon-key",
            "KEYCHAIN_ACCESS_GROUP": "ABCDE12345.ai.sidebar.sidebar",
            "KEYCHAIN_SERVICE": "ai.sidebar.sidebar",
        }
    )
    return env


def test_ci_post_clone_writes_optional_sentry_dsn(tmp_path: Path) -> None:
    """Xcode Cloud config generation should preserve the optional Sentry DSN."""
    repo_root = make_temp_repo(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(bin_dir / "swiftlint", "#!/bin/bash\nexit 0\n")

    env = required_env(repo_root, bin_dir)
    env["SENTRY_DSN"] = "https://public@example.ingest.sentry.io/123"

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr

    generated = (repo_root / "ios" / "sideBar" / "Config" / "SideBar.local.xcconfig").read_text(
        encoding="utf-8"
    )
    assert "SENTRY_DSN = https:\\/\\/public@example.ingest.sentry.io\\/123" in generated
    assert "INFOPLIST_KEY_SENTRY_DSN = $(SENTRY_DSN)" in generated


def test_ci_post_clone_skips_sentry_cli_install_without_sentry_upload_env(tmp_path: Path) -> None:
    """The post-clone script should not attempt sentry-cli install without upload secrets."""
    repo_root = make_temp_repo(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(bin_dir / "swiftlint", "#!/bin/bash\nexit 0\n")
    write_executable(
        bin_dir / "curl",
        "#!/bin/bash\necho 'curl should not be called' >&2\nexit 99\n",
    )

    env = required_env(repo_root, bin_dir)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "Sentry dSYM upload disabled" in result.stdout
