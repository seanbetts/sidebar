"""Tests for scripts/check_ios_extension_config_resolution.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "check_ios_extension_config_resolution.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "check_ios_extension_config_resolution", MODULE_PATH
)
assert MODULE_SPEC is not None and MODULE_SPEC.loader is not None
CONFIG_CHECK_MODULE = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(CONFIG_CHECK_MODULE)

LOCAL_INCLUDE_LINE = CONFIG_CHECK_MODULE.LOCAL_INCLUDE_LINE

evaluate_setting_expectations = CONFIG_CHECK_MODULE.evaluate_setting_expectations
has_relative_local_include = CONFIG_CHECK_MODULE.has_relative_local_include
main = CONFIG_CHECK_MODULE.main
parse_build_settings = CONFIG_CHECK_MODULE.parse_build_settings
validate_extension_config_resolution = CONFIG_CHECK_MODULE.validate_extension_config_resolution


def test_has_relative_local_include_accepts_expected_line() -> None:
    """Checker should accept a relative local include line."""
    text = f"// comment\n{LOCAL_INCLUDE_LINE}\n"

    assert has_relative_local_include(text) is True


def test_has_relative_local_include_rejects_srcroot_include() -> None:
    """Checker should reject the previous SRCROOT-based include form."""
    text = '#include? "$(SRCROOT)/Config/SideBar.local.xcconfig"\n'

    assert has_relative_local_include(text) is False


def test_parse_build_settings_normalizes_escaped_values() -> None:
    """Parsed build settings should normalize escaped URL values."""
    output = """
        API_BASE_URL = http:\\/\\/127.0.0.1:8001\\/api\\/v1
        INFOPLIST_KEY_API_BASE_URL = http://127.0.0.1:8001/api/v1
    """

    parsed = parse_build_settings(output)

    assert parsed["API_BASE_URL"] == "http://127.0.0.1:8001/api/v1"
    assert parsed["INFOPLIST_KEY_API_BASE_URL"] == "http://127.0.0.1:8001/api/v1"


def test_evaluate_setting_expectations_reports_unresolved_value() -> None:
    """Unresolved placeholder values should produce actionable failures."""
    errors = evaluate_setting_expectations(
        target="sideBar Safari Extension",
        settings={"API_BASE_URL": "$(API_BASE_URL)"},
        expectations={"API_BASE_URL": "https://example.invalid/api"},
    )

    assert len(errors) == 1
    assert "unresolved" in errors[0]


def test_validate_extension_config_resolution_uses_temp_local_override(
    monkeypatch,
    tmp_path: Path,
) -> None:
    """Validator should require sentinel values to surface in target build settings."""
    base_xcconfig = tmp_path / "SideBar.xcconfig"
    base_xcconfig.write_text(f"{LOCAL_INCLUDE_LINE}\n", encoding="utf-8")

    expected = CONFIG_CHECK_MODULE.SETTING_EXPECTATIONS

    def fake_show_build_settings(*, project_path, target, configuration, xcconfig_path):
        del project_path, target, configuration
        temp_dir = xcconfig_path.parent
        local_config = (temp_dir / "SideBar.local.xcconfig").read_text(encoding="utf-8")
        assert "config-resolution.example.invalid" in local_config
        return "\n".join([f"{key} = {value}" for key, value in expected.items()])

    monkeypatch.setattr(
        CONFIG_CHECK_MODULE,
        "run_show_build_settings",
        fake_show_build_settings,
    )

    errors = validate_extension_config_resolution(
        project_path=tmp_path / "sideBar.xcodeproj",
        base_xcconfig_path=base_xcconfig,
        configuration="Debug",
        targets=("sideBar Safari Extension",),
    )

    assert errors == []


def test_main_returns_failure_when_required_files_missing(monkeypatch, tmp_path: Path) -> None:
    """CLI should fail fast for missing project/xcconfig paths."""
    missing_project = tmp_path / "missing.xcodeproj"
    missing_xcconfig = tmp_path / "missing.xcconfig"

    monkeypatch.setattr(
        "sys.argv",
        [
            "check_ios_extension_config_resolution.py",
            "--project",
            str(missing_project),
            "--base-xcconfig",
            str(missing_xcconfig),
        ],
    )

    assert main() == 1
