"""
Shared pytest fixtures for sidebar tests.
"""

import os
import json
import tempfile
from pathlib import Path
import pytest

# CRITICAL: Set TESTING=1 before any application imports
# This ensures Settings loads from .env.test instead of .env
os.environ["TESTING"] = "1"

# Also set individual env vars as a fallback
# These are mock values - never use real secrets in tests
os.environ.setdefault("AUTH_DEV_MODE", "true")
os.environ.setdefault("DEFAULT_USER_ID", "81326b53-b7eb-42e2-b645-0c03cb5d5dd4")
os.environ.setdefault("ANTHROPIC_API_KEY", "test-anthropic-key-12345")
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key-12345")
os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test",
)
os.environ.setdefault("WORKSPACE_BASE", "/tmp/test-workspace")
os.environ.setdefault(
    "SKILLS_DIR",
    str(Path(__file__).resolve().parents[1] / "skills"),
)

# Ensure all SQLAlchemy models are registered before metadata operations.
from api.models.conversation import Conversation  # noqa: F401
from api.models.note import Note  # noqa: F401
from api.models.website import Website  # noqa: F401
from api.models.user_settings import UserSettings  # noqa: F401
from api.models.user_memory import UserMemory  # noqa: F401
from api.models.file_object import FileObject  # noqa: F401
from api.models.file_ingestion import IngestedFile, FileDerivative, FileProcessingJob  # noqa: F401


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
    return json.dumps({
        "type": "service_account",
        "project_id": "test-project-12345",
        "private_key_id": "test-key-id-123",
        "private_key": "-----BEGIN PRIVATE KEY-----\nMOCK_PRIVATE_KEY_DATA\n-----END PRIVATE KEY-----\n",
        "client_email": "test-service-account@test-project.iam.gserviceaccount.com",
        "client_id": "123456789012345678901",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/test-service-account%40test-project.iam.gserviceaccount.com"
    })


@pytest.fixture
def mock_drive_service():
    """
    Create a mock Google Drive service for testing.

    Returns a MagicMock that simulates the Google Drive API client with common operations.
    """
    from unittest.mock import MagicMock, Mock

    service = MagicMock()

    # Mock files().list() response
    list_response = {
        'files': [
            {
                'id': '1abc123def456',
                'name': 'test-document.pdf',
                'mimeType': 'application/pdf',
                'size': '123456',
                'modifiedTime': '2025-01-15T10:30:00.000Z',
                'createdTime': '2025-01-01T12:00:00.000Z',
                'owners': [{'emailAddress': 'owner@example.com', 'displayName': 'Test Owner'}],
                'parents': ['0BxRootFolder']
            },
            {
                'id': '2xyz789ghi012',
                'name': 'spreadsheet.xlsx',
                'mimeType': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                'size': '45678',
                'modifiedTime': '2025-01-14T09:15:00.000Z',
                'createdTime': '2025-01-10T08:00:00.000Z',
                'owners': [{'emailAddress': 'owner@example.com', 'displayName': 'Test Owner'}],
                'parents': ['0BxRootFolder']
            }
        ],
        'nextPageToken': None
    }
    service.files().list().execute.return_value = list_response

    # Mock files().get() response (metadata)
    get_response = {
        'id': '1abc123def456',
        'name': 'test-document.pdf',
        'mimeType': 'application/pdf',
        'size': '123456',
        'modifiedTime': '2025-01-15T10:30:00.000Z',
        'createdTime': '2025-01-01T12:00:00.000Z',
        'owners': [{'emailAddress': 'owner@example.com', 'displayName': 'Test Owner'}],
        'parents': ['0BxRootFolder'],
        'webViewLink': 'https://drive.google.com/file/d/1abc123def456/view',
        'permissions': [
            {'type': 'user', 'role': 'owner', 'emailAddress': 'owner@example.com'}
        ]
    }
    service.files().get().execute.return_value = get_response

    # Mock files().create() response (upload)
    create_response = {
        'id': '3new456file789',
        'name': 'uploaded-file.txt',
        'mimeType': 'text/plain',
        'webViewLink': 'https://drive.google.com/file/d/3new456file789/view'
    }
    service.files().create().execute.return_value = create_response

    # Mock about().get() response (used for auth testing)
    about_response = {
        'user': {
            'emailAddress': 'test-service-account@test-project.iam.gserviceaccount.com',
            'displayName': 'Test Service Account'
        }
    }
    service.about().get().execute.return_value = about_response

    return service


@pytest.fixture
def mock_env_vars(monkeypatch, mock_service_account_json):
    """Set up mock environment variables for Google Drive testing."""
    monkeypatch.setenv('GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON', mock_service_account_json)


# Database test fixtures

@pytest.fixture(scope="session")
def test_db_engine():
    """
    Create a test database engine for PostgreSQL.

    This is a session-scoped fixture that creates the test database schema once
    and tears it down after all tests complete.
    """
    from sqlalchemy import create_engine, text
    from api.db.base import Base
    from api.models import (
        conversation,
        note,
        website,
        user_settings,
        user_memory,
        file_object,
    )

    # Use the test database URL
    test_db_url = os.getenv("DATABASE_URL", "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test")

    # Create engine
    engine = create_engine(test_db_url, pool_pre_ping=True)

    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception as exc:
        engine.dispose()
        pytest.skip(f"Test database unavailable: {exc}")

    # Create all tables
    Base.metadata.create_all(engine)

    yield engine

    # Cleanup: Drop all tables after all tests
    Base.metadata.drop_all(engine)
    engine.dispose()


@pytest.fixture
def test_db(test_db_engine):
    """
    Create a clean database session for each test.

    This fixture provides a database session and ensures that all changes
    are rolled back after each test, maintaining test isolation.
    """
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy import text
    from api.db.base import Base

    # Create session
    TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_db_engine)
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
    """
    Create a FastAPI test client.

    This fixture provides a test client for making requests to API endpoints.
    The client automatically handles authentication and database sessions.
    """
    from fastapi.testclient import TestClient
    from api.main import app

    with TestClient(app) as client:
        yield client
