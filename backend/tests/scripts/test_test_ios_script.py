import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "test-ios.sh"


def write_executable(path: Path, contents: str) -> None:
    path.write_text(contents)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def write_xcodebuild_logger(path: Path, log_path: Path) -> None:
    write_executable(
        path,
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" >> \"{log_path}\"\n"
        "exit 0\n",
    )


def write_xcrun_stub(
    path: Path,
    *,
    devices_json: str,
    runtimes_json: str,
    device_types_json: str,
    created_udid: str = "PREPUSH-UDID-1234",
) -> None:
    script = f"""#!/bin/bash
if [[ "$1 $2 $3" == "simctl list devices" ]]; then
  cat <<'EOF'
{devices_json}
EOF
  exit 0
fi
if [[ "$1 $2 $3" == "simctl list runtimes" ]]; then
  cat <<'EOF'
{runtimes_json}
EOF
  exit 0
fi
if [[ "$1 $2 $3" == "simctl list devicetypes" ]]; then
  cat <<'EOF'
{device_types_json}
EOF
  exit 0
fi
if [[ "$1 $2" == "simctl create" ]]; then
  echo {created_udid}
  exit 0
fi
exit 0
"""
    write_executable(path, script)


def pre_push_env(bin_dir: Path, **overrides: str) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "SIDEBAR_PRE_PUSH_MODE": "YES",
            "SIDEBAR_PRE_PUSH_STATE_DIR": str(bin_dir.parent / "state"),
            "SIDEBAR_PRE_PUSH_SIMULATOR_NAME": "sideBar PrePush iPad",
            "IOS_DESTINATION": "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
        }
    )
    env.update(overrides)
    return env


AVAILABLE_IOS_RUNTIMES_JSON = """
{"runtimes":[
  {
    "identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-2",
    "isAvailable":true,
    "platform":"iOS",
    "version":"26.2"
  }
]}
""".strip()


EMPTY_IOS_RUNTIMES_JSON = """
{"runtimes":[]}
""".strip()


IPAD_DEVICE_TYPES_JSON = """
{"devicetypes":[
  {
    "name":"iPad Pro 13-inch (M5)",
    "identifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5"
  }
]}
""".strip()


EMPTY_DEVICE_TYPES_JSON = """
{"devicetypes":[]}
""".strip()


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


def test_default_scheme_uses_canonical_sidebar_app_tests(tmp_path: Path) -> None:
    """The shell harness should default to the canonical shared app-test scheme."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\nexit 0\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_DESTINATION": "platform=macOS",
            "IOS_ENABLE_CODE_COVERAGE": "NO",
        }
    )
    env.pop("IOS_SCHEME", None)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "Running Apple tests for scheme sideBar " in result.stdout


def test_ui_only_lane_fails_when_backend_config_is_missing(tmp_path: Path) -> None:
    """UI-only lanes should fail closed when required backend config is absent."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\n"
        "echo 'xcodebuild should not have been invoked' >&2\n"
        "exit 99\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_SCHEME": "sideBarUI",
            "IOS_ONLY_TESTING": "sideBarUITests",
            "IOS_DESTINATION": "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
            "SIDEBAR_UI_TEST_SECRETS_FILE": str(tmp_path / "missing-ui-secrets.local"),
        }
    )
    for key in (
        "API_BASE_URL",
        "SUPABASE_URL",
        "SUPABASE_ANON_KEY",
        "SIDEBAR_UI_TEST_API_BASE_URL",
        "SIDEBAR_UI_TEST_SUPABASE_URL",
        "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY",
    ):
        env.pop(key, None)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1, result.stdout + result.stderr
    assert "UI test backend configuration missing" in result.stdout


def test_ui_only_lane_fails_when_credentials_are_missing(tmp_path: Path) -> None:
    """UI-only lanes should fail closed when auth credentials are absent."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\n"
        "echo 'xcodebuild should not have been invoked' >&2\n"
        "exit 99\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_SCHEME": "sideBarUI",
            "IOS_ONLY_TESTING": "sideBarUITests",
            "IOS_DESTINATION": "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
            "SIDEBAR_UI_TEST_API_BASE_URL": "https://api.sidebar.example/api/v1",
            "SIDEBAR_UI_TEST_SUPABASE_URL": "https://sidebar.supabase.co",
            "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY": "anon-key",
            "SIDEBAR_UI_TEST_SECRETS_FILE": str(tmp_path / "missing-ui-secrets.local"),
        }
    )
    for key in (
        "SIDEBAR_UI_TEST_EMAIL",
        "SIDEBAR_UI_TEST_PASSWORD",
    ):
        env.pop(key, None)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1, result.stdout + result.stderr
    assert "UI test credentials missing" in result.stdout


def test_ui_only_lane_accepts_secrets_file_inputs(tmp_path: Path) -> None:
    """UI-only lanes should accept backend/auth values from the secrets file."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\nexit 0\n",
    )

    secrets_file = tmp_path / ".ui-test-secrets.local"
    secrets_file.write_text(
        "\n".join(
            [
                "SIDEBAR_UI_TEST_EMAIL=tester@example.com",
                "SIDEBAR_UI_TEST_PASSWORD=super-secret",
                "SIDEBAR_UI_TEST_API_BASE_URL=https://api.sidebar.example/api/v1",
                "SIDEBAR_UI_TEST_SUPABASE_URL=https://sidebar.supabase.co",
                "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY=anon-key",
            ]
        )
    )

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_SCHEME": "sideBarUI",
            "IOS_ONLY_TESTING": "sideBarUITests",
            "IOS_DESTINATION": "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
            "SIDEBAR_UI_TEST_SECRETS_FILE": str(secrets_file),
        }
    )
    for key in (
        "SIDEBAR_UI_TEST_EMAIL",
        "SIDEBAR_UI_TEST_PASSWORD",
        "SIDEBAR_UI_TEST_API_BASE_URL",
        "SIDEBAR_UI_TEST_SUPABASE_URL",
        "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY",
    ):
        env.pop(key, None)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr


def test_ui_resolve_only_lane_skips_backend_preflight(tmp_path: Path) -> None:
    """Resolve-only UI warmup should succeed without UI backend or auth secrets."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "xcodebuild.log"
    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" > \"{log_path}\"\n"
        "exit 0\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_SCHEME": "sideBarUI",
            "IOS_DESTINATION": "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
            "IOS_RESOLVE_PACKAGE_DEPENDENCIES_ONLY": "YES",
            "SIDEBAR_UI_TEST_SECRETS_FILE": str(tmp_path / "missing-ui-secrets.local"),
        }
    )
    for key in (
        "API_BASE_URL",
        "SUPABASE_URL",
        "SUPABASE_ANON_KEY",
        "SIDEBAR_UI_TEST_API_BASE_URL",
        "SIDEBAR_UI_TEST_SUPABASE_URL",
        "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY",
        "SIDEBAR_UI_TEST_EMAIL",
        "SIDEBAR_UI_TEST_PASSWORD",
    ):
        env.pop(key, None)

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "Package resolution complete; exiting before test execution." in result.stdout
    assert "UI test backend configuration missing" not in result.stdout
    assert "-resolvePackageDependencies" in log_path.read_text()


def test_package_resolution_retry_clears_swiftpm_artifacts_cache(
    tmp_path: Path,
) -> None:
    """Resolve retries should clear the global SwiftPM artifacts cache."""
    home_dir = tmp_path / "home"
    artifacts_dir = home_dir / "Library" / "Caches" / "org.swift.swiftpm" / "artifacts"
    repositories_dir = home_dir / "Library" / "Caches" / "org.swift.swiftpm" / "repositories"
    manifests_dir = home_dir / "Library" / "Caches" / "org.swift.swiftpm" / "manifests"
    artifacts_dir.mkdir(parents=True)
    repositories_dir.mkdir(parents=True)
    manifests_dir.mkdir(parents=True)
    (artifacts_dir / "Sentry.xcframework.zip").write_text("stale artifact")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\n"
        "if [[ \"$*\" == *\"-resolvePackageDependencies\"* ]]; then\n"
        f"  if [[ -d \"{artifacts_dir}\" ]]; then\n"
        "    exit 1\n"
        "  fi\n"
        "fi\n"
        "exit 0\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home_dir),
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_DESTINATION": "platform=macOS",
            "IOS_ENABLE_CODE_COVERAGE": "NO",
            "IOS_PACKAGE_RESOLVE_RETRIES": "2",
            "IOS_PACKAGE_RESOLVE_RETRY_DELAY_SECONDS": "0",
            "IOS_CLEAN_GLOBAL_SWIFTPM_CACHE_ON_RETRY": "YES",
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
    assert not artifacts_dir.exists()


def test_package_resolution_uses_persistent_swiftpm_paths_and_resolved_versions(
    tmp_path: Path,
) -> None:
    """SwiftPM resolution should use persistent caches, not disposable DerivedData."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    xcodebuild_log = tmp_path / "xcodebuild.log"
    cloned_packages_dir = tmp_path / "swiftpm-clones"
    package_cache_dir = tmp_path / "swiftpm-cache"
    derived_data_dir = tmp_path / "derived-data"

    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" >> \"{xcodebuild_log}\"\n"
        "exit 0\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "GITHUB_ACTIONS": "true",
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_DESTINATION": "platform=macOS",
            "IOS_ENABLE_CODE_COVERAGE": "NO",
            "IOS_DERIVED_DATA_PATH": str(derived_data_dir),
            "IOS_CLONED_SOURCE_PACKAGES_DIR": str(cloned_packages_dir),
            "IOS_PACKAGE_CACHE_PATH": str(package_cache_dir),
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
    log_lines = xcodebuild_log.read_text().splitlines()
    assert len(log_lines) == 2

    resolve_args, test_args = log_lines
    for args in (resolve_args, test_args):
        assert f"-clonedSourcePackagesDirPath {cloned_packages_dir}" in args
        assert f"-packageCachePath {package_cache_dir}" in args
        assert "-onlyUsePackageVersionsFromResolvedFile" in args
        assert "-skipPackageUpdates" in args

    assert f"-derivedDataPath {derived_data_dir}" in resolve_args
    assert f"-derivedDataPath {derived_data_dir}" in test_args
    assert "-resolvePackageDependencies" in resolve_args
    assert "-disableAutomaticPackageResolution" in test_args


def test_resolve_only_mode_exits_after_package_resolution(tmp_path: Path) -> None:
    """Warmup mode should resolve packages and exit before invoking the test action."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    xcodebuild_log = tmp_path / "xcodebuild.log"

    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" >> \"{xcodebuild_log}\"\n"
        "exit 0\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_DESTINATION": "platform=macOS",
            "IOS_ENABLE_CODE_COVERAGE": "NO",
            "IOS_RESOLVE_PACKAGE_DEPENDENCIES_ONLY": "YES",
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
    log_lines = xcodebuild_log.read_text().splitlines()
    assert len(log_lines) == 1
    assert "-resolvePackageDependencies" in log_lines[0]
    assert " test" not in log_lines[0]


def test_skip_package_resolution_mode_runs_tests_without_explicit_resolve(
    tmp_path: Path,
) -> None:
    """Test lanes should be able to skip the pre-resolve step after a warm phase."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    xcodebuild_log = tmp_path / "xcodebuild.log"

    write_executable(
        bin_dir / "xcodebuild",
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$*\" >> \"{xcodebuild_log}\"\n"
        "exit 0\n",
    )

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env['PATH']}",
            "IOS_DESTINATION": "platform=macOS",
            "IOS_ENABLE_CODE_COVERAGE": "NO",
            "IOS_SKIP_PACKAGE_DEPENDENCY_RESOLUTION": "YES",
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
    log_lines = xcodebuild_log.read_text().splitlines()
    assert len(log_lines) == 1
    assert "-resolvePackageDependencies" not in log_lines[0]
    assert " test" in log_lines[0]


def test_pre_push_mode_creates_dedicated_simulator_and_rewrites_destination(
    tmp_path: Path,
) -> None:
    """Pre-push mode should target a dedicated simulator by UDID."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    xcodebuild_log = tmp_path / "xcodebuild.log"
    write_xcodebuild_logger(bin_dir / "xcodebuild", xcodebuild_log)
    write_xcrun_stub(
        bin_dir / "xcrun",
        devices_json='{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[]}}',
        runtimes_json=AVAILABLE_IOS_RUNTIMES_JSON,
        device_types_json=IPAD_DEVICE_TYPES_JSON,
    )

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=pre_push_env(bin_dir),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "-destination platform=iOS Simulator,id=PREPUSH-UDID-1234" in xcodebuild_log.read_text()
    assert (tmp_path / "state" / "simulator-udid").read_text().strip() == "PREPUSH-UDID-1234"


def test_pre_push_mode_reuses_existing_simulator_udid(tmp_path: Path) -> None:
    """Pre-push mode should reuse an existing dedicated simulator."""
    state_dir = tmp_path / "state"
    state_dir.mkdir()
    (state_dir / "simulator-udid").write_text("EXISTING-UDID-1234")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    xcodebuild_log = tmp_path / "xcodebuild.log"
    create_log = tmp_path / "xcrun-create.log"
    write_xcodebuild_logger(bin_dir / "xcodebuild", xcodebuild_log)
    write_executable(
        bin_dir / "xcrun",
        "#!/bin/bash\n"
        "if [[ \"$1 $2 $3\" == \"simctl list devices\" ]]; then\n"
        "  cat <<'EOF'\n"
        '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"name":"sideBar PrePush iPad","udid":"EXISTING-UDID-1234","isAvailable":true,"state":"Shutdown"}]}}\n'
        "EOF\n"
        "  exit 0\n"
        "fi\n"
        "if [[ \"$1 $2 $3\" == \"simctl list runtimes\" ]]; then\n"
        "  cat <<'EOF'\n"
        f"{AVAILABLE_IOS_RUNTIMES_JSON}\n"
        "EOF\n"
        "  exit 0\n"
        "fi\n"
        "if [[ \"$1 $2 $3\" == \"simctl list devicetypes\" ]]; then\n"
        "  cat <<'EOF'\n"
        f"{IPAD_DEVICE_TYPES_JSON}\n"
        "EOF\n"
        "  exit 0\n"
        "fi\n"
        "if [[ \"$1 $2\" == \"simctl create\" ]]; then\n"
        f"  printf '%s\\n' \"$*\" >> \"{create_log}\"\n"
        "  echo SHOULD-NOT-BE-USED\n"
        "  exit 0\n"
        "fi\n"
        "exit 0\n",
    )

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=pre_push_env(bin_dir, SIDEBAR_PRE_PUSH_STATE_DIR=str(state_dir)),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "-destination platform=iOS Simulator,id=EXISTING-UDID-1234" in xcodebuild_log.read_text()
    assert not create_log.exists()


def test_pre_push_mode_recovers_from_stale_udid(tmp_path: Path) -> None:
    """Pre-push mode should replace a stale UDID with the current simulator UDID."""
    state_dir = tmp_path / "state"
    state_dir.mkdir()
    (state_dir / "simulator-udid").write_text("STALE-UDID-1234")

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    xcodebuild_log = tmp_path / "xcodebuild.log"
    write_xcodebuild_logger(bin_dir / "xcodebuild", xcodebuild_log)
    write_xcrun_stub(
        bin_dir / "xcrun",
        devices_json='{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"name":"sideBar PrePush iPad","udid":"VALID-UDID-5678","isAvailable":true,"state":"Shutdown"}]}}',
        runtimes_json=AVAILABLE_IOS_RUNTIMES_JSON,
        device_types_json=IPAD_DEVICE_TYPES_JSON,
        created_udid="VALID-UDID-5678",
    )

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=pre_push_env(bin_dir, SIDEBAR_PRE_PUSH_STATE_DIR=str(state_dir)),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "-destination platform=iOS Simulator,id=VALID-UDID-5678" in xcodebuild_log.read_text()
    assert (state_dir / "simulator-udid").read_text().strip() == "VALID-UDID-5678"


def test_pre_push_mode_fails_when_no_ios_runtime_is_available(tmp_path: Path) -> None:
    """Pre-push mode should fail clearly when no iOS runtime can be resolved."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_xcodebuild_logger(bin_dir / "xcodebuild", tmp_path / "xcodebuild.log")
    write_xcrun_stub(
        bin_dir / "xcrun",
        devices_json='{"devices":{}}',
        runtimes_json=EMPTY_IOS_RUNTIMES_JSON,
        device_types_json=IPAD_DEVICE_TYPES_JSON,
    )

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=pre_push_env(bin_dir),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1, result.stdout + result.stderr
    assert "Error: could not resolve an available iOS simulator runtime for pre-push mode." in result.stdout


def test_pre_push_mode_fails_when_device_type_cannot_be_resolved(
    tmp_path: Path,
) -> None:
    """Pre-push mode should fail clearly when the simulator device type is missing."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    write_xcodebuild_logger(bin_dir / "xcodebuild", tmp_path / "xcodebuild.log")
    write_xcrun_stub(
        bin_dir / "xcrun",
        devices_json='{"devices":{}}',
        runtimes_json=AVAILABLE_IOS_RUNTIMES_JSON,
        device_types_json=EMPTY_DEVICE_TYPES_JSON,
    )

    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd=REPO_ROOT,
        env=pre_push_env(bin_dir),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1, result.stdout + result.stderr
    assert (
        "Error: could not resolve simulator device type for destination "
        "platform=iOS Simulator,name=iPad Pro 13-inch (M5)."
    ) in result.stdout
