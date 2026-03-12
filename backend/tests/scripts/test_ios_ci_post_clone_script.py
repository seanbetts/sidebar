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
            "SENTRY_AUTH_TOKEN": "token",
            "SENTRY_ORG": "sidebar",
            "SENTRY_PROJECT": "apple",
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


def test_ci_post_clone_keeps_sentry_keys_available_when_dsn_is_unset(tmp_path: Path) -> None:
    """Xcode Cloud config generation should keep the Sentry keys available even when blank."""
    repo_root = make_temp_repo(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(bin_dir / "swiftlint", "#!/bin/bash\nexit 0\n")

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

    generated = (repo_root / "ios" / "sideBar" / "Config" / "SideBar.local.xcconfig").read_text(
        encoding="utf-8"
    )
    assert "SENTRY_DSN = " in generated
    assert "INFOPLIST_KEY_SENTRY_DSN = $(SENTRY_DSN)" in generated


def test_ci_post_clone_preserves_sentry_upload_variables_for_later_steps(tmp_path: Path) -> None:
    """The post-clone step should leave upload credentials available for a later upload hook."""
    repo_root = make_temp_repo(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(bin_dir / "swiftlint", "#!/bin/bash\nexit 0\n")

    env = required_env(repo_root, bin_dir)
    env["SENTRY_DSN"] = "https://public@example.ingest.sentry.io/123"

    result = subprocess.run(
        [
            "bash",
            "-lc",
            (
                f'source "{SCRIPT_PATH}" >/dev/null && '
                'printf "AUTH=%s\\nORG=%s\\nPROJECT=%s\\n" '
                '"$SENTRY_AUTH_TOKEN" "$SENTRY_ORG" "$SENTRY_PROJECT"'
            ),
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "AUTH=token" in result.stdout
    assert "ORG=sidebar" in result.stdout
    assert "PROJECT=apple" in result.stdout


def test_ci_post_clone_runs_carthage_update_when_a_cartfile_exists(tmp_path: Path) -> None:
    """Xcode Cloud bootstrap should build Carthage dependencies before project builds."""
    repo_root = make_temp_repo(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    carthage_log = tmp_path / "carthage.log"
    (repo_root / "ios" / "sideBar" / "Cartfile").write_text(
        'github "getsentry/sentry-cocoa" == 8.55.1\n',
        encoding="utf-8",
    )
    write_executable(bin_dir / "swiftlint", "#!/bin/bash\nexit 0\n")
    write_executable(
        bin_dir / "carthage",
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" >> \"{carthage_log}\"\n"
        "exit 0\n",
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
    assert "bootstrap --use-xcframeworks --platform iOS,macOS --cache-builds" in carthage_log.read_text(
        encoding="utf-8"
    )
