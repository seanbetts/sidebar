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


def test_ci_post_clone_has_no_apple_sentry_package_manager_bootstrap() -> None:
    """Xcode Cloud should not try to install Apple Sentry through a package manager."""
    script = SCRIPT_PATH.read_text(encoding="utf-8").lower()

    assert "carthage" not in script
    assert "pod install" not in script
    assert "sentry-cocoa" not in script


def test_ci_post_clone_installs_sentry_cli_best_effort_when_upload_is_enabled(tmp_path: Path) -> None:
    """Xcode Cloud should provision sentry-cli when dSYM upload credentials are present."""
    repo_root = make_temp_repo(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    install_log = tmp_path / "sentry-install.log"
    write_executable(bin_dir / "swiftlint", "#!/bin/bash\nexit 0\n")
    write_executable(
        bin_dir / "curl",
        (
            "#!/bin/bash\n"
            "cat <<'SCRIPT'\n"
            "#!/bin/bash\n"
            "mkdir -p \"${INSTALL_DIR}\"\n"
            "printf '%s\\n' \"${SENTRY_CLI_VERSION}\" > \"" + str(install_log) + "\"\n"
            "cat > \"${INSTALL_DIR}/sentry-cli\" <<'EOF'\n"
            "#!/bin/bash\n"
            "exit 0\n"
            "EOF\n"
            "chmod +x \"${INSTALL_DIR}/sentry-cli\"\n"
            "SCRIPT\n"
        ),
    )

    env = required_env(repo_root, bin_dir)
    env["SENTRY_CLI_VERSION"] = "2.58.2"
    env["PATH"] = f"{bin_dir}:/usr/bin:/bin"

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    installed_cli = repo_root / "ios" / "sideBar" / ".tools" / "sentry-cli" / "bin" / "sentry-cli"
    assert installed_cli.exists()
    assert install_log.read_text(encoding="utf-8").strip() == "2.58.2"
