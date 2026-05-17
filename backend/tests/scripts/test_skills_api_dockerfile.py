"""Guardrails for the skills API Docker image."""

from pathlib import Path
import re
import tomllib


REPO_ROOT = Path(__file__).resolve().parents[3]
DOCKERFILE = REPO_ROOT / "backend" / "docker" / "Dockerfile.skills-api"
PYPROJECT = REPO_ROOT / "backend" / "pyproject.toml"
REQUIREMENTS = REPO_ROOT / "backend" / "api" / "requirements.txt"
CONSTRAINTS = REPO_ROOT / "backend" / "api" / "constraints.txt"
UV_LOCK = REPO_ROOT / "backend" / "uv.lock"


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


def test_apns_runtime_dependencies_include_http2_support() -> None:
    pyproject = tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))
    pyproject_dependencies = pyproject["project"]["dependencies"]
    requirements = REQUIREMENTS.read_text(encoding="utf-8").splitlines()
    dockerfile_contents = DOCKERFILE.read_text(encoding="utf-8")

    assert any(
        dependency.startswith("httpx[http2]")
        for dependency in pyproject_dependencies
    )
    assert any(
        requirement.startswith("httpx[http2]")
        for requirement in requirements
        if requirement and not requirement.startswith("#")
    )
    assert "COPY api/requirements.txt ./requirements.txt" in dockerfile_contents
    assert "-r requirements.txt" in dockerfile_contents


def test_skills_api_mcp_runtime_dependencies_match_locked_stack() -> None:
    """The Fly image must not downgrade FastMCP below the locked runtime stack."""
    requirements = _dependency_map(REQUIREMENTS.read_text(encoding="utf-8"))
    constraints = _dependency_map(CONSTRAINTS.read_text(encoding="utf-8"))
    locked = _locked_versions(
        "authlib",
        "fastmcp",
        "mcp",
        "pydantic",
        "pydantic-core",
    )

    assert requirements["fastmcp"] == f">={locked['fastmcp']}"
    assert requirements["mcp"] == ">=1.24.0"
    assert constraints["authlib"] == f"=={locked['authlib']}"
    assert constraints["fastmcp"] == f"=={locked['fastmcp']}"
    assert constraints["mcp"] == f"=={locked['mcp']}"
    assert constraints["pydantic"] == f"=={locked['pydantic']}"
    assert constraints["pydantic-core"] == f"=={locked['pydantic-core']}"
    dockerfile_contents = DOCKERFILE.read_text(encoding="utf-8")
    editable_install = dockerfile_contents.split("-e .", maxsplit=1)[0]
    assert "-c constraints.txt" in editable_install


def _dependency_map(contents: str) -> dict[str, str]:
    dependencies: dict[str, str] = {}
    for line in contents.splitlines():
        if not line or line.startswith(("#", "-")):
            continue
        match = re.match(r"([A-Za-z0-9_.-]+)(.*)", line)
        assert match is not None
        dependencies[match.group(1).lower()] = match.group(2)
    return dependencies


def _locked_versions(*names: str) -> dict[str, str]:
    lock = tomllib.loads(UV_LOCK.read_text(encoding="utf-8"))
    versions = {package["name"]: package["version"] for package in lock["package"]}
    return {name: versions[name] for name in names}
