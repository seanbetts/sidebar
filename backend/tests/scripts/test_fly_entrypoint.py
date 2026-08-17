"""Regression tests for Fly container startup guardrails."""

import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
ENTRYPOINT_PATH = REPO_ROOT / "backend" / "docker" / "entrypoint.sh"
FLY_TOML_PATH = REPO_ROOT / "backend" / "fly.toml"


def test_entrypoint_avoids_recursive_data_volume_chown() -> None:
    """App startup should not walk the entire /data volume before binding the port."""
    contents = ENTRYPOINT_PATH.read_text(encoding="utf-8")

    assert "chown -R appuser:appuser /data" not in contents
    assert "chown appuser:appuser /data || true" in contents


def test_entrypoint_allows_app_process_to_skip_playwright_startup_check() -> None:
    """App machines should be able to bypass Playwright preflight during HTTP startup."""
    contents = ENTRYPOINT_PATH.read_text(encoding="utf-8")

    assert "SKIP_PLAYWRIGHT_STARTUP_CHECK:-0" in contents


def test_fly_supplies_playwright_skip_before_entrypoint_evaluates_guard() -> None:
    """Fly should expose the skip flag before ENTRYPOINT inspects its environment."""
    config = tomllib.loads(FLY_TOML_PATH.read_text(encoding="utf-8"))

    assert config["env"].get("SKIP_PLAYWRIGHT_STARTUP_CHECK") == "1"
