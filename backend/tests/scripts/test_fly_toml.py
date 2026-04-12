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


def test_fly_declares_dedicated_website_process_group() -> None:
    """Fly should run website processing in its own process group."""
    contents = FLY_TOML.read_text(encoding="utf-8")

    assert 'website = "python -m workers.website_processing_worker"' in contents


def test_fly_sets_initial_website_worker_concurrency_to_two() -> None:
    """Fly should cap initial website worker concurrency at two."""
    contents = FLY_TOML.read_text(encoding="utf-8")

    assert 'WEBSITE_WORKER_CONCURRENCY = "2"' in contents
