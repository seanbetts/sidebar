"""
Shared pytest fixtures for agent-smith tests.
"""

import json
import tempfile
from pathlib import Path
import pytest


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
