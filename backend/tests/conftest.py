"""Shared pytest fixtures for sidebar tests.
"""

import json
import os
import subprocess
import tempfile
from pathlib import Path

import pytest
from tests.db_config import (
    LOCAL_TEST_DATABASE_URL,
    build_supabase_test_database_url,
    is_placeholder_value,
    resolve_default_test_database_url,
    use_supabase_test_db,
    validate_supabase_test_env,
)

# CRITICAL: Set TESTING=1 before any application imports
# This ensures Settings loads from .env.test instead of .env
os.environ["TESTING"] = "1"


# Load TEST_USER_ID from .env.test if not already set.
def _load_env_file(
    path: Path,
    allowed_prefixes: tuple[str, ...] | None = None,
    *,
    override: bool = False,
) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if allowed_prefixes and not key.startswith(allowed_prefixes):
            continue
        if override or key not in os.environ:
            os.environ[key] = value.strip()


def _read_doppler_secret(name: str) -> str:
    """Best-effort read of a Doppler secret."""
    try:
        return subprocess.check_output(
            ["doppler", "secrets", "get", name, "--plain"],
            text=True,
        ).strip()
    except Exception:
        return ""


def _hydrate_supabase_password_from_doppler() -> None:
    """Populate hosted test DB password from Doppler when placeholders are present."""
    if not os.getenv("DOPPLER_TOKEN"):
        return

    postgres_password = (os.getenv("SUPABASE_POSTGRES_PSWD") or "").strip()
    if not is_placeholder_value(postgres_password):
        return

    legacy_app_password = (os.getenv("SUPABASE_APP_PSWD") or "").strip()
    if not is_placeholder_value(legacy_app_password):
        os.environ["SUPABASE_POSTGRES_PSWD"] = legacy_app_password
        return

    for key in ("SUPABASE_POSTGRES_TEST_PSWD", "SUPABASE_POSTGRES_PSWD", "SUPABASE_APP_PSWD"):
        value = _read_doppler_secret(key)
        if not is_placeholder_value(value):
            os.environ["SUPABASE_POSTGRES_PSWD"] = value
            break


env_test_path = Path(__file__).resolve().parents[1] / ".env.test"
env_local_path = Path(__file__).resolve().parents[2] / ".env.local"
_load_env_file(env_test_path)
_load_env_file(
    env_local_path,
    allowed_prefixes=("DOPPLER_",),
)

# Also set individual env vars as a fallback
# These are mock values - never use real secrets in tests
os.environ.setdefault("AUTH_DEV_MODE", "false")
TEST_USER_ID = os.getenv("TEST_USER_ID")
if not TEST_USER_ID:
    raise RuntimeError("TEST_USER_ID must be set for tests to avoid production data.")
os.environ.setdefault("ANTHROPIC_API_KEY", "test-anthropic-key-12345")
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key-12345")
os.environ.setdefault("BEARER_TOKEN", "test-bearer-token")
os.environ.setdefault("SUPABASE_POSTGRES_PSWD", "test-supabase-postgres-password")
os.environ.setdefault("WORKSPACE_BASE", "/tmp/test-workspace")
os.environ.setdefault(
    "SKILLS_DIR",
    str(Path(__file__).resolve().parents[1] / "skills"),
)

auth_dev_mode = os.getenv("AUTH_DEV_MODE", "").lower() in {"1", "true", "yes", "on"}
if not auth_dev_mode and not os.getenv("BEARER_TOKEN"):
    supabase_url = os.getenv("SUPABASE_URL")
    api_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_ANON_KEY")
    email = os.getenv("TEST_USER_EMAIL")
    password = os.getenv("TEST_USER_PASSWORD")
    if supabase_url and api_key and email and password:
        try:
            import httpx

            response = httpx.post(
                f"{supabase_url}/auth/v1/token?grant_type=password",
                headers={"apikey": api_key, "Content-Type": "application/json"},
                json={"email": email, "password": password},
                timeout=10.0,
            )
            response.raise_for_status()
            token = response.json().get("access_token")
            if token:
                os.environ.setdefault("BEARER_TOKEN", token)
        except Exception:
            pass

use_supabase_db = use_supabase_test_db(os.environ)
if use_supabase_db:
    # Hosted test lane must use explicit test credentials from .env.test rather
    # than inheriting workstation-local Supabase settings.
    _load_env_file(
        env_test_path,
        allowed_prefixes=("SUPABASE_", "DATABASE_URL"),
        override=True,
    )
    _hydrate_supabase_password_from_doppler()

    supabase_config_errors = validate_supabase_test_env(os.environ)
    if supabase_config_errors:
        formatted_errors = "\n".join(f"- {error}" for error in supabase_config_errors)
        raise RuntimeError(
            "USE_SUPABASE_TEST_DB=1 requires dedicated hosted test DB credentials.\n"
            f"{formatted_errors}"
        )

    hosted_url = build_supabase_test_database_url(os.environ)
    if not hosted_url:
        raise RuntimeError(
            "USE_SUPABASE_TEST_DB=1 requires a Supabase DATABASE_URL or pooler env config."
        )
    os.environ["DATABASE_URL"] = hosted_url
else:
    os.environ["DATABASE_URL"] = resolve_default_test_database_url(os.environ)

# Ensure all SQLAlchemy models are registered before metadata operations.
from api.models.conversation import Conversation  # noqa: F401, E402
from api.models.device_token import DeviceToken  # noqa: F401, E402
from api.models.file_ingestion import (  # noqa: F401, E402
    FileDerivative,
    FileProcessingJob,
    IngestedFile,
)
from api.models.note import Note  # noqa: F401, E402
from api.models.user_memory import UserMemory  # noqa: F401, E402
from api.models.user_ai_provider_key import UserAIProviderKey  # noqa: F401, E402
from api.models.user_skill_state import UserSkillState  # noqa: F401, E402
from api.models.user_settings import UserSettings  # noqa: F401, E402
from api.models.website import Website  # noqa: F401, E402
from api.models.website_processing_job import WebsiteProcessingJob  # noqa: F401, E402


def _ensure_user_settings_columns(connection) -> None:
    """Ensure additive user_settings columns exist for incremental schema tests."""
    from sqlalchemy import text

    connection.execute(
        text(
            "ALTER TABLE user_settings "
            "ADD COLUMN IF NOT EXISTS ai_primary_provider text"
        )
    )
    connection.execute(
        text(
            "ALTER TABLE conversations "
            "ADD COLUMN IF NOT EXISTS ai_provider text"
        )
    )
    connection.execute(
        text(
            "ALTER TABLE conversations "
            "ADD COLUMN IF NOT EXISTS ai_model text"
        )
    )
    connection.execute(
        text(
            "CREATE TABLE IF NOT EXISTS user_ai_provider_keys ("
            "id uuid PRIMARY KEY, "
            "user_id text NOT NULL, "
            "provider text NOT NULL, "
            "encrypted_api_key text NOT NULL, "
            "key_last4 text NOT NULL, "
            "created_at timestamptz NOT NULL, "
            "updated_at timestamptz NOT NULL, "
            "deleted_at timestamptz NULL"
            ")"
        )
    )
    connection.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_user_ai_provider_keys_user_id "
            "ON user_ai_provider_keys (user_id)"
        )
    )
    connection.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_user_ai_provider_keys_provider "
            "ON user_ai_provider_keys (provider)"
        )
    )
    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS "
            "uq_user_ai_provider_keys_active_user_provider "
            "ON user_ai_provider_keys (user_id, provider) "
            "WHERE deleted_at IS NULL"
        )
    )
    connection.execute(
        text(
            "CREATE TABLE IF NOT EXISTS user_skill_states ("
            "id uuid PRIMARY KEY, "
            "user_id text NOT NULL, "
            "skill_id text NOT NULL, "
            "enabled boolean NOT NULL DEFAULT false, "
            "installed boolean NOT NULL DEFAULT false, "
            "metadata jsonb NOT NULL DEFAULT '{}'::jsonb, "
            "created_at timestamptz NOT NULL, "
            "updated_at timestamptz NOT NULL, "
            "deleted_at timestamptz NULL"
            ")"
        )
    )
    connection.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_user_skill_states_user_id "
            "ON user_skill_states (user_id)"
        )
    )
    connection.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_user_skill_states_skill_id "
            "ON user_skill_states (skill_id)"
        )
    )
    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS "
            "uq_user_skill_states_active_user_skill "
            "ON user_skill_states (user_id, skill_id) "
            "WHERE deleted_at IS NULL"
        )
    )


@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def sample_skill_dir(temp_dir):
    """Create a sample skill directory with valid SKILL.md."""
    skill_dir = temp_dir / "test-skill"
    skill_dir.mkdir()

    skill_md = skill_dir / "SKILL.md"
    skill_md.write_text("""---
name: test-skill
description: A test skill for unit testing
---

# Test Skill

This is a test skill.
""")

    return skill_dir


@pytest.fixture
def sample_pyproject_toml(temp_dir):
    """Create a sample pyproject.toml file."""
    toml_file = temp_dir / "pyproject.toml"
    toml_file.write_text("""[project]
name = "test-project"
version = "0.1.0"
description = "Test project"
requires-python = ">=3.11"

dependencies = [
    "requests>=2.31.0",
]
""")
    return toml_file


@pytest.fixture
def fixtures_dir():
    """Return path to test fixtures directory."""
    return Path(__file__).parent / "fixtures"


@pytest.fixture
def sample_skill_with_scripts(temp_dir):
    """Create a skill with scripts/ directory containing Python files."""
    skill_dir = temp_dir / "test-skill"
    skill_dir.mkdir()

    # Create SKILL.md
    (skill_dir / "SKILL.md").write_text("""---
name: test-skill
description: Test skill with scripts
---

# Test Skill
""")

    # Create scripts/ with Python files
    scripts_dir = skill_dir / "scripts"
    scripts_dir.mkdir()

    # Script with external imports
    (scripts_dir / "example.py").write_text("""
import sys
import json
import requests
from PIL import Image
import numpy as np
""")

    return skill_dir


@pytest.fixture
def sample_python_file_with_imports(temp_dir):
    """Create a Python file with various types of imports."""
    py_file = temp_dir / "test.py"
    py_file.write_text("""
import sys
import json
import requests
from PIL import Image
from datetime import datetime
import numpy as np
""")
    return py_file


def create_json_stream(data: dict):
    """Helper to create a JSON stream from data (for PDF tests)."""
    import io

    return io.StringIO(json.dumps(data))


# Google Drive test fixtures


@pytest.fixture
def mock_service_account_json():
    """Return a mock service account JSON for testing Google Drive authentication."""
    return json.dumps(
        {
            "type": "service_account",
            "project_id": "test-project-12345",
            "private_key_id": "test-key-id-123",
            "private_key": "-----BEGIN PRIVATE KEY-----\nMOCK_PRIVATE_KEY_DATA\n-----END PRIVATE KEY-----\n",
            "client_email": "test-service-account@test-project.iam.gserviceaccount.com",
            "client_id": "123456789012345678901",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
            "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/test-service-account%40test-project.iam.gserviceaccount.com",
        }
    )


@pytest.fixture
def mock_drive_service():
    """Create a mock Google Drive service for testing.

    Returns a MagicMock that simulates the Google Drive API client with common operations.
    """
    from unittest.mock import MagicMock

    service = MagicMock()

    # Mock files().list() response
    list_response = {
        "files": [
            {
                "id": "1abc123def456",
                "name": "test-document.pdf",
                "mimeType": "application/pdf",
                "size": "123456",
                "modifiedTime": "2025-01-15T10:30:00.000Z",
                "createdTime": "2025-01-01T12:00:00.000Z",
                "owners": [
                    {"emailAddress": "owner@example.com", "displayName": "Test Owner"}
                ],
                "parents": ["0BxRootFolder"],
            },
            {
                "id": "2xyz789ghi012",
                "name": "spreadsheet.xlsx",
                "mimeType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "size": "45678",
                "modifiedTime": "2025-01-14T09:15:00.000Z",
                "createdTime": "2025-01-10T08:00:00.000Z",
                "owners": [
                    {"emailAddress": "owner@example.com", "displayName": "Test Owner"}
                ],
                "parents": ["0BxRootFolder"],
            },
        ],
        "nextPageToken": None,
    }
    service.files().list().execute.return_value = list_response

    # Mock files().get() response (metadata)
    get_response = {
        "id": "1abc123def456",
        "name": "test-document.pdf",
        "mimeType": "application/pdf",
        "size": "123456",
        "modifiedTime": "2025-01-15T10:30:00.000Z",
        "createdTime": "2025-01-01T12:00:00.000Z",
        "owners": [{"emailAddress": "owner@example.com", "displayName": "Test Owner"}],
        "parents": ["0BxRootFolder"],
        "webViewLink": "https://drive.google.com/file/d/1abc123def456/view",
        "permissions": [
            {"type": "user", "role": "owner", "emailAddress": "owner@example.com"}
        ],
    }
    service.files().get().execute.return_value = get_response

    # Mock files().create() response (upload)
    create_response = {
        "id": "3new456file789",
        "name": "uploaded-file.txt",
        "mimeType": "text/plain",
        "webViewLink": "https://drive.google.com/file/d/3new456file789/view",
    }
    service.files().create().execute.return_value = create_response

    # Mock about().get() response (used for auth testing)
    about_response = {
        "user": {
            "emailAddress": "test-service-account@test-project.iam.gserviceaccount.com",
            "displayName": "Test Service Account",
        }
    }
    service.about().get().execute.return_value = about_response

    return service


@pytest.fixture
def mock_env_vars(monkeypatch, mock_service_account_json):
    """Set up mock environment variables for Google Drive testing."""
    monkeypatch.setenv("GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON", mock_service_account_json)


# Database test fixtures


@pytest.fixture(scope="session")
def test_db_engine():
    """Create a test database engine for PostgreSQL.

    This is a session-scoped fixture that validates database connectivity.
    Schema lifecycle for the local lane is Alembic-managed via setup_test_db.sh.
    """
    from sqlalchemy import create_engine, text

    # Use the test database URL
    test_db_url = os.getenv("DATABASE_URL", LOCAL_TEST_DATABASE_URL)

    # Create engine
    engine = create_engine(test_db_url, pool_pre_ping=True)

    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception as exc:
        engine.dispose()
        pytest.skip(f"Test database unavailable: {exc}")

    yield engine

    engine.dispose()


@pytest.fixture
def test_db(test_db_engine):
    """Create a clean database session for each test.

    This fixture provides a database session and ensures that all changes
    are rolled back after each test, maintaining test isolation.
    """
    from api.db.base import Base
    from sqlalchemy import text
    from sqlalchemy.orm import sessionmaker

    with test_db_engine.begin() as setup_connection:
        setup_connection.execute(text("SET search_path TO public"))
        _ensure_user_settings_columns(setup_connection)

    if use_supabase_db:
        connection = test_db_engine.connect()
        transaction = connection.begin()
        TestSessionLocal = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=connection,
            join_transaction_mode="create_savepoint",
        )
        db = TestSessionLocal()
        db.info["force_public_search_path"] = True
        db.execute(text("SET search_path TO public"))

        try:
            yield db
        finally:
            db.close()
            transaction.rollback()
            connection.close()
        return

    # Local lane keeps deterministic table cleanup between tests because API
    # requests run in separate sessions and can otherwise leak state.
    TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_db_engine)
    db = TestSessionLocal()
    db.info["force_public_search_path"] = True
    db.execute(text("SET search_path TO public"))

    try:
        yield db
    finally:
        db.rollback()
        db.close()

        with test_db_engine.connect() as cleanup_connection:
            cleanup_connection.execute(text("SET search_path TO public"))
            for table in reversed(Base.metadata.sorted_tables):
                cleanup_connection.execute(text(f"TRUNCATE TABLE {table.name} CASCADE"))
            cleanup_connection.commit()


@pytest.fixture(scope="session")
def test_client(test_db_engine):
    """Create a FastAPI test client.

    This fixture provides a test client for making requests to API endpoints.
    The client automatically handles authentication and database sessions.
    """
    from api.db import session as db_session
    from api.main import app
    from fastapi.testclient import TestClient

    db_session.engine = test_db_engine
    db_session.SessionLocal.configure(bind=test_db_engine)

    with TestClient(app) as client:
        yield client
