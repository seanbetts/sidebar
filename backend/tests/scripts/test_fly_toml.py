"""Guardrails for Fly runtime configuration."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
FLY_TOML = REPO_ROOT / "backend" / "fly.toml"


def test_fly_defaults_ytdlp_js_runtimes_to_deno_then_node() -> None:
    contents = FLY_TOML.read_text(encoding="utf-8")

    assert 'YT_DLP_JS_RUNTIMES = "deno,node"' in contents


def test_fly_http_service_uses_longer_startup_grace_period() -> None:
    contents = FLY_TOML.read_text(encoding="utf-8")

    assert 'grace_period = "60s"' in contents


def test_fly_sets_production_apns_environment() -> None:
    contents = FLY_TOML.read_text(encoding="utf-8")

    assert 'APNS_ENV = "prod"' in contents
