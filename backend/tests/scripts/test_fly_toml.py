"""Guardrails for Fly runtime configuration."""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[3]
FLY_TOML = REPO_ROOT / "backend" / "fly.toml"


def _fly_config() -> dict[str, Any]:
    """Parse the committed Fly configuration."""
    return tomllib.loads(FLY_TOML.read_text(encoding="utf-8"))


def _restart_policy(config: dict[str, Any], process_group: str) -> str | None:
    """Return the restart policy assigned to one process group."""
    for rule in config.get("restart", []):
        if process_group in rule.get("processes", []):
            return rule.get("policy")
    return None


def _vm_memory(config: dict[str, Any], process_group: str) -> str | None:
    """Return the VM memory assigned to one process group."""
    rules = config.get("vm", [])
    if isinstance(rules, dict):
        rules = [rules]
    for rule in rules:
        if process_group in rule.get("processes", []):
            return rule.get("memory")
    return None


def test_fly_uses_plain_dedicated_process_commands() -> None:
    """Fly commands should stay plain because ENTRYPOINT reads environment first."""
    config = _fly_config()

    assert config["processes"] == {
        "app": "uvicorn api.main:app --host 0.0.0.0 --port 8001",
        "ingestion": "python -m workers.ingestion_worker",
        "notification": "python -m workers.worker_runner",
        "website": "python -m workers.website_processing_worker",
    }


def test_fly_enables_safe_demand_lifecycle_defaults() -> None:
    """Production defaults should enable demand control with bounded idle exits."""
    config = _fly_config()
    env = config["env"]

    assert env["WORKER_DEMAND_MONITOR_ENABLED"] == "true"
    assert env["WORKER_DEMAND_POLL_SECONDS"] == "1"
    assert env["WEBSITE_WORKER_IDLE_EXIT_SECONDS"] == "30"
    assert env["INGESTION_WORKER_IDLE_EXIT_SECONDS"] == "30"
    assert env["NOTIFICATION_SCHEDULE_INTERVAL_SECONDS"] == "300"
    assert env["FLY_WORKER_CONTROL_APP"] == "sidebar-api"


def test_fly_api_scales_to_zero_with_proxy_autostart() -> None:
    """Fly Proxy should suspend and resume only the API process group on demand."""
    service = _fly_config()["http_service"]

    assert service["processes"] == ["app"]
    assert service["auto_stop_machines"] == "suspend"
    assert service["auto_start_machines"] is True
    assert service["min_machines_running"] == 0


def test_fly_restart_policies_keep_only_control_always_on() -> None:
    """Clean demand-worker exits should stop while control always restarts."""
    config = _fly_config()

    assert _restart_policy(config, "notification") == "always"
    assert _restart_policy(config, "app") == "on-failure"
    assert _restart_policy(config, "website") == "on-failure"
    assert _restart_policy(config, "ingestion") == "on-failure"


def test_fly_keeps_every_process_group_at_one_gigabyte_initially() -> None:
    """The initial rollout should reduce runtime, not impose unsafe memory limits."""
    config = _fly_config()

    assert {
        process_group: _vm_memory(config, process_group)
        for process_group in ("app", "notification", "website", "ingestion")
    } == {
        "app": "1024mb",
        "notification": "1024mb",
        "website": "1024mb",
        "ingestion": "1024mb",
    }


def test_fly_keeps_data_mount_scoped_to_api() -> None:
    """Demand workers and control must not acquire the API data volume."""
    config = _fly_config()

    assert config["mounts"] == [
        {
            "source": "data",
            "destination": "/data",
            "processes": ["app"],
        }
    ]


def test_fly_preserves_existing_runtime_defaults() -> None:
    """Unrelated production runtime settings should survive lifecycle changes."""
    config = _fly_config()

    assert config["env"]["YT_DLP_JS_RUNTIMES"] == "deno,node"
    assert config["env"]["APNS_ENV"] == "prod"
    assert config["env"]["WEBSITE_WORKER_CONCURRENCY"] == "2"
    assert config["http_service"]["checks"][0]["grace_period"] == "60s"
