"""Guardrails for the main backend Docker image."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
DOCKERFILE = REPO_ROOT / "backend" / "docker" / "Dockerfile.skills-api"


def test_backend_image_installs_tzdata_for_scheduler_timezones() -> None:
    """Timezone-aware notification scheduling requires IANA timezone data."""
    contents = DOCKERFILE.read_text(encoding="utf-8")

    assert "tzdata" in contents
    assert "apt-get install -y --no-install-recommends" in contents
