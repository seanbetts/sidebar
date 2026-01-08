"""Shared pytest fixtures for sidebar tests.
"""

import json
import os
import subprocess
import tempfile
from pathlib import Path

import pytest

# CRITICAL: Set TESTING=1 before any application imports
# This ensures Settings loads from .env.test instead of .env
os.environ["TESTING"] = "1"


# Load TEST_USER_ID from .env.test if not already set.
def _load_env_file(path: Path, allowed_prefixes: tuple[str, ...] | None = None) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if allowed_prefixes and not key.startswith(allowed_prefixes):
            continue
        os.environ.setdefault(key, value.strip())


env_test_path = Path(__file__).resolve().parents[1] / ".env.test"
env_local_path = Path(__file__).resolve().parents[2] / ".env.local"
_load_env_file(env_test_path)
_load_env_file(env_local_path, allowed_prefixes=("SUPABASE_", "DOPPLER_"))

# Also set individual env vars as a fallback
# These are mock values - never use real secrets in tests
os.environ.setdefault("AUTH_DEV_MODE", "false")
TEST_USER_ID = os.getenv("TEST_USER_ID")
if not TEST_USER_ID:
    raise RuntimeError("TEST_USER_ID must be set for tests to avoid production data.")
os.environ.setdefault("ANTHROPIC_API_KEY", "test-anthropic-key-12345")
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key-12345")
os.environ.setdefault("WORKSPACE_BASE", "/tmp/test-workspace")
os.environ.setdefault(
    "SKILLS_DIR",
    str(Path(__file__).resolve().parents[1] / "skills"),
)

if os.getenv("DOPPLER_TOKEN"):
    anon_key = os.getenv("SUPABASE_ANON_KEY", "")
    if not anon_key or anon_key.startswith("test-"):
        try:
            value = subprocess.check_output(
                ["doppler", "secrets", "get", "SUPABASE_ANON_KEY", "--plain"],
                text=True,
            ).strip()
            if value:
                os.environ["SUPABASE_ANON_KEY"] = value
        except Exception:
            pass

if not os.getenv("SUPABASE_SERVICE_ROLE_KEY") and os.getenv("DOPPLER_TOKEN"):
    for key in ("SUPABASE_SERVICE_ROLE_TEST_KEY", "SUPABASE_SERVICE_ROLE_KEY"):
        try:
            value = subprocess.check_output(
                ["doppler", "secrets", "get", key, "--plain"],
                text=True,
            ).strip()
            if value:
                os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", value)
                break
        except Exception:
            continue

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

database_url = os.getenv("DATABASE_URL", "")
if "localhost" in database_url or "127.0.0.1" in database_url or not database_url:
    if not os.getenv("SUPABASE_POSTGRES_PSWD") and os.getenv("DOPPLER_TOKEN"):
        for key in ("SUPABASE_POSTGRES_TEST_PSWD", "SUPABASE_POSTGRES_PSWD"):
            try:
                password = subprocess.check_output(
                    ["doppler", "secrets", "get", key, "--plain"],
                    text=True,
                ).strip()
                if password:
                    os.environ.setdefault("SUPABASE_POSTGRES_PSWD", password)
                    break
            except Exception:
                continue

    if os.getenv("SUPABASE_POOLER_USER", "").startswith(
        "sidebar_app"
    ) and not os.getenv("SUPABASE_APP_PSWD"):
        try:
            password = subprocess.check_output(
                ["doppler", "secrets", "get", "SUPABASE_APP_PSWD", "--plain"],
                text=True,
            ).strip()
            if password:
                os.environ.setdefault("SUPABASE_APP_PSWD", password)
        except Exception:
            pass

    if os.getenv("SUPABASE_POSTGRES_PSWD") and os.getenv("SUPABASE_PROJECT_ID"):
        try:
            from api.config import _build_database_url

            os.environ.pop("DATABASE_URL", None)
            os.environ["DATABASE_URL"] = _build_database_url()
        except Exception:
            pass

if not os.getenv("SUPABASE_PROJECT_ID"):
    os.environ.setdefault(
        "DATABASE_URL",
        "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test",
    )

# Ensure all SQLAlchemy models are registered before metadata operations.
from api.models.conversation import Conversation  # noqa: F401, E402
from api.models.file_ingestion import (  # noqa: F401, E402
    FileDerivative,
    FileProcessingJob,
    IngestedFile,
)
from api.models.note import Note  # noqa: F401, E402
from api.models.user_memory import UserMemory  # noqa: F401, E402
from api.models.user_settings import UserSettings  # noqa: F401, E402
from api.models.website import Website  # noqa: F401, E402
from api.models.website_processing_job import WebsiteProcessingJob  # noqa: F401, E402


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

    This is a session-scoped fixture that creates the test database schema once
    and tears it down after all tests complete.
    """
    from api.db.base import Base
    from sqlalchemy import create_engine, text

    # Use the test database URL
    test_db_url = os.getenv(
        "DATABASE_URL", "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test"
    )

    # Create engine
    engine = create_engine(test_db_url, pool_pre_ping=True)

    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception as exc:
        engine.dispose()
        pytest.skip(f"Test database unavailable: {exc}")

    # Create all tables in public schema
    with engine.connect() as connection:
        connection.execute(text("SET search_path TO public"))
        Base.metadata.create_all(bind=connection)

    yield engine

    # Cleanup: Drop all tables after all tests
    with engine.connect() as connection:
        connection.execute(text("SET search_path TO public"))
        Base.metadata.drop_all(bind=connection)
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

    # Create session
    TestSessionLocal = sessionmaker(
        autocommit=False, autoflush=False, bind=test_db_engine
    )
    db = TestSessionLocal()
    db.execute(text("SET search_path TO public"))
    Base.metadata.create_all(bind=db.connection())

    try:
        yield db
    finally:
        # Rollback any uncommitted changes
        db.rollback()

        # Clean up all data from tables (but keep schema)
        # This ensures each test starts with a clean state
        for table in reversed(Base.metadata.sorted_tables):
            db.execute(text(f"TRUNCATE TABLE {table.name} CASCADE"))
        db.commit()

        db.close()


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
