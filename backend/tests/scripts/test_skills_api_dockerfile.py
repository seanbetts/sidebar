"""Guardrails for the skills API Docker image."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
DOCKERFILE = REPO_ROOT / "backend" / "docker" / "Dockerfile.skills-api"


def test_skills_api_image_installs_ffmpeg() -> None:
    contents = DOCKERFILE.read_text(encoding="utf-8")

    assert "ffmpeg" in contents
    assert "apt-get install -y --no-install-recommends" in contents
