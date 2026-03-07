import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "test-ios.sh"


def write_executable(path: Path, contents: str) -> None:
    path.write_text(contents)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def test_ci_uses_temp_git_config_when_global_config_is_locked(tmp_path: Path) -> None:
    home_dir = tmp_path / "home"
    home_dir.mkdir()
    (home_dir / ".gitconfig").write_text("[user]\n\tname = CI Test\n")
    (home_dir / ".gitconfig.lock").write_text("locked\n")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\nexit 0\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "GITHUB_ACTIONS": "true",
            "HOME": str(home_dir),
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_DESTINATION": "platform=macOS",
            "IOS_ENABLE_CODE_COVERAGE": "NO",
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
    assert (home_dir / ".gitconfig.lock").exists()
