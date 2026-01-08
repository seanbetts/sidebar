#!/usr/bin/env python3
"""Shared environment setup for database-backed scripts."""

from __future__ import annotations

import getpass
import logging
import os
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlencode, urlparse


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def _load_doppler_env() -> None:
    token = os.environ.get("DOPPLER_TOKEN")
    if not token or not shutil.which("doppler"):
        return
    project = os.environ.get("DOPPLER_PROJECT")
    config = os.environ.get("DOPPLER_CONFIG")
    if not project or not config:
        return
    result = subprocess.run(
        [
            "doppler",
            "secrets",
            "download",
            "--no-file",
            "--format",
            "env",
            "--project",
            project,
            "--config",
            config,
        ],
        check=False,
        capture_output=True,
        text=True,
        env={**os.environ, "DOPPLER_TOKEN": token},
    )
    if result.returncode != 0:
        logging.warning("Doppler secrets download failed: %s", result.stderr.strip())
        return
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ[key.strip()] = value.strip()


def _normalize_supabase_passwords() -> None:
    pooler_user = os.environ.get("SUPABASE_POOLER_USER", "")
    if pooler_user.startswith("sidebar_app") and os.environ.get(
        "SUPABASE_POSTGRES_PSWD"
    ):
        os.environ.setdefault("SUPABASE_APP_PSWD", os.environ["SUPABASE_POSTGRES_PSWD"])


def _build_pooler_database_url() -> str | None:
    pooler_url = os.environ.get("SUPABASE_POOLER_URL")
    pooler_host = os.environ.get("SUPABASE_POOLER_HOST")
    password = os.environ.get("SUPABASE_APP_PSWD") or os.environ.get(
        "SUPABASE_POSTGRES_PSWD"
    )
    username = os.environ.get("SUPABASE_POOLER_USER")
    db_name = os.environ.get("SUPABASE_DB_NAME", "postgres")
    sslmode = os.environ.get("SUPABASE_SSLMODE", "require")
    pooler_mode = os.environ.get("SUPABASE_POOLER_MODE", "transaction").lower()
    port = os.environ.get("SUPABASE_POOLER_PORT", "6543")

    parsed = urlparse(pooler_url) if pooler_url else None
    hostname = None
    if parsed and parsed.hostname:
        hostname = parsed.hostname
        username = username or parsed.username
        if parsed.path and parsed.path.strip("/"):
            db_name = parsed.path.strip("/")
        if parsed.port:
            port = str(parsed.port)
        if parsed.password:
            password = parsed.password
    elif pooler_host:
        hostname = pooler_host

    if pooler_mode == "transaction":
        port = "6543"

    if not hostname or not username or not password:
        return None

    netloc = f"{username}:{password}@{hostname}:{port}"
    query = urlencode({"sslmode": sslmode})
    return f"postgresql://{netloc}/{db_name}?{query}"


def _seed_database_env() -> None:
    url = _build_pooler_database_url()
    if url:
        os.environ["DATABASE_URL"] = url


def _ensure_supabase_password(*, force: bool = False) -> None:
    if not force and (
        os.environ.get("SUPABASE_APP_PSWD") or os.environ.get("SUPABASE_POSTGRES_PSWD")
    ):
        return
    password = getpass.getpass("Supabase DB password: ").strip()
    if not password:
        raise RuntimeError("Supabase DB password is required to run this script.")
    os.environ["SUPABASE_APP_PSWD"] = password


def _ensure_database_config(*, force_prompt: bool = False) -> None:
    if os.environ.get("DATABASE_URL"):
        parsed = urlparse(os.environ["DATABASE_URL"])
        logging.info(
            "Using database host=%s port=%s user=%s",
            parsed.hostname,
            parsed.port,
            parsed.username,
        )
        return
    _ensure_supabase_password(force=force_prompt)
    _seed_database_env()
    if os.environ.get("DATABASE_URL"):
        return
    raise RuntimeError("Failed to build DATABASE_URL from Supabase settings.")


def setup_environment(
    *,
    database_url: str | None = None,
    supabase: bool = False,
    set_anthropic_placeholder: bool = True,
) -> None:
    """Load env/Doppler settings and configure DATABASE_URL for scripts."""
    repo_root = Path(__file__).resolve().parents[2]
    backend_root = repo_root / "backend"

    _load_env_file(repo_root / ".env.local")
    _load_env_file(repo_root / ".env")
    _load_env_file(backend_root / ".env.local")
    _load_env_file(backend_root / ".env")
    _load_doppler_env()
    _normalize_supabase_passwords()

    if database_url:
        os.environ["DATABASE_URL"] = database_url
        _ensure_database_config()
    elif supabase:
        os.environ.pop("DATABASE_URL", None)
        _ensure_supabase_password(force=True)
        _seed_database_env()
        _ensure_database_config()
    else:
        _ensure_database_config()

    if set_anthropic_placeholder:
        os.environ.setdefault("ANTHROPIC_API_KEY", "local-dev-placeholder")
