"""Guardrails for the skills API Docker image."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
DOCKERFILE = REPO_ROOT / "backend" / "docker" / "Dockerfile.skills-api"


def test_skills_api_image_installs_ffmpeg() -> None:
    contents = DOCKERFILE.read_text(encoding="utf-8")

    assert "ffmpeg" in contents
    assert "apt-get install -y --no-install-recommends" in contents


def test_skills_api_image_installs_deno() -> None:
    contents = DOCKERFILE.read_text(encoding="utf-8")

    assert "deno" in contents


def test_skills_api_healthcheck_targets_api_health_without_curl() -> None:
    contents = DOCKERFILE.read_text(encoding="utf-8")
    healthcheck_section = contents.split("HEALTHCHECK", maxsplit=1)[1]

    assert "HEALTHCHECK" in contents
    assert "http://127.0.0.1:8001/api/health" in contents
    assert "curl -f" not in healthcheck_section


def test_skills_api_image_uses_system_ca_bundle_for_python_https() -> None:
    contents = DOCKERFILE.read_text(encoding="utf-8")

    assert "REQUESTS_CA_BUNDLE=/usr/lib/ssl/cert.pem" in contents
    assert "SSL_CERT_FILE=/usr/lib/ssl/cert.pem" in contents
