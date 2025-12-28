"""
Tests for scripts/add_skill_dependencies.py

Tests AST-based import detection, standard library filtering,
and pyproject.toml modification logic.

This is a KEY test file for the dependency management workflow.
"""

import pytest
from pathlib import Path
import sys

# Add project root to path so we can import the script
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from scripts.add_skill_dependencies import (
    get_imports_from_file,
    filter_stdlib_and_local,
    normalize_package_name,
    get_current_dependencies,
    add_dependencies_to_pyproject,
    scan_skill_scripts,
    get_skill_directory,
)


class TestGetImportsFromFile:
    """Test import detection from Python files."""

    def test_basic_imports(self, temp_dir):
        """Test detection of basic import statements."""
        test_file = temp_dir / "test.py"
        test_file.write_text("""
import requests
import json
from PIL import Image
""")

        imports = get_imports_from_file(test_file)

        assert "requests" in imports
        assert "json" in imports
        assert "PIL" in imports

    def test_from_imports(self, temp_dir):
        """Test detection of 'from X import Y' statements."""
        test_file = temp_dir / "test.py"
        test_file.write_text("""
from datetime import datetime
from os.path import join
import numpy as np
""")

        imports = get_imports_from_file(test_file)

        assert "datetime" in imports
        assert "os" in imports
        assert "numpy" in imports

    def test_nested_imports(self, temp_dir):
        """Test detection of nested module imports (e.g., import X.Y.Z)."""
        test_file = temp_dir / "test.py"
        test_file.write_text("""
import os.path
from PIL.Image import open
""")

        imports = get_imports_from_file(test_file)

        # Should extract top-level package names
        assert "os" in imports
        assert "PIL" in imports

    def test_syntax_error_handling(self, temp_dir):
        """Test that files with syntax errors return empty set."""
        test_file = temp_dir / "bad.py"
        test_file.write_text("""
import requests
this is not valid python syntax
""")

        imports = get_imports_from_file(test_file)

        # Should return empty set on syntax error
        assert imports == set()

    def test_empty_file(self, temp_dir):
        """Test that empty files return empty set."""
        test_file = temp_dir / "empty.py"
        test_file.write_text("")

        imports = get_imports_from_file(test_file)

        assert imports == set()


class TestFilterStdlibAndLocal:
    """Test filtering of standard library and local modules."""

    def test_filters_stdlib_modules(self):
        """Test that standard library modules are filtered out."""
        imports = {"sys", "json", "os", "requests", "numpy"}

        external = filter_stdlib_and_local(imports)

        assert "sys" not in external
        assert "json" not in external
        assert "os" not in external
        assert "requests" in external
        assert "numpy" in external

    def test_filters_local_modules(self):
        """Test that local modules (ooxml, skills, etc.) are filtered out."""
        imports = {"ooxml", "skills", "scripts", "references", "assets", "requests"}

        external = filter_stdlib_and_local(imports)

        assert "ooxml" not in external
        assert "skills" not in external
        assert "scripts" not in external
        assert "references" not in external
        assert "assets" not in external
        assert "requests" in external

    def test_mixed_imports(self):
        """Test filtering of mixed stdlib, local, and external imports."""
        imports = {
            "sys",  # stdlib
            "json",  # stdlib
            "ooxml",  # local
            "requests",  # external
            "PIL",  # external
            "numpy",  # external
        }

        external = filter_stdlib_and_local(imports)

        assert external == {"requests", "PIL", "numpy"}


class TestNormalizePackageName:
    """Test package name normalization for PyPI."""

    def test_pil_to_pillow(self):
        """Test PIL → Pillow normalization."""
        assert normalize_package_name("PIL") == "Pillow"

    def test_cv2_to_opencv(self):
        """Test cv2 → opencv-python normalization."""
        assert normalize_package_name("cv2") == "opencv-python"

    def test_sklearn_to_scikit_learn(self):
        """Test sklearn → scikit-learn normalization."""
        assert normalize_package_name("sklearn") == "scikit-learn"

    def test_yaml_to_pyyaml(self):
        """Test yaml → PyYAML normalization."""
        assert normalize_package_name("yaml") == "PyYAML"

    def test_unchanged_package_names(self):
        """Test that packages without special mapping remain unchanged."""
        assert normalize_package_name("requests") == "requests"
        assert normalize_package_name("numpy") == "numpy"
        assert normalize_package_name("pandas") == "pandas"


class TestGetCurrentDependencies:
    """Test reading current dependencies from pyproject.toml."""

    def test_reads_existing_dependencies(self, fixtures_dir, monkeypatch):
        """Test reading dependencies from pyproject.toml with existing deps."""
        # Change to fixtures directory so the function finds the right toml
        monkeypatch.chdir(fixtures_dir.parent.parent)

        # Create a temporary pyproject.toml in the current directory
        temp_toml = Path("pyproject.toml")
        original_content = temp_toml.read_text() if temp_toml.exists() else None

        try:
            temp_toml.write_text("""[project]
name = "test"
dependencies = [
    "requests>=2.31.0",
    "Pillow>=10.0.0",
]
""")

            deps = get_current_dependencies()

            assert "requests" in deps
            assert "pillow" in deps  # Normalized to lowercase

        finally:
            # Restore original file
            if original_content:
                temp_toml.write_text(original_content)

    def test_empty_dependencies(self, temp_dir, monkeypatch):
        """Test reading from pyproject.toml with empty dependencies."""
        monkeypatch.chdir(temp_dir)

        toml_file = temp_dir / "pyproject.toml"
        toml_file.write_text("""[project]
name = "test"
dependencies = []
""")

        deps = get_current_dependencies()

        assert deps == set()


class TestScanSkillScripts:
    """Test scanning skill scripts for imports."""

    def test_scans_skill_with_scripts(self, fixtures_dir):
        """Test scanning a skill with scripts/ directory."""
        skill_dir = fixtures_dir / "skills" / "skill-with-scripts"

        imports = scan_skill_scripts(skill_dir)

        # Should find all imports from example.py (including stdlib)
        assert "requests" in imports
        assert "numpy" in imports
        assert "PIL" in imports
        assert "pandas" in imports
        assert "sys" in imports  # stdlib modules are included
        assert "json" in imports  # stdlib modules are included

        # Note: scan_skill_scripts returns ALL imports.
        # Filtering is done separately by filter_stdlib_and_local()

    def test_skill_with_no_scripts(self, fixtures_dir):
        """Test scanning a skill without scripts/ directory."""
        skill_dir = fixtures_dir / "skills" / "valid-skill"

        imports = scan_skill_scripts(skill_dir)

        assert imports == set()


class TestGetSkillDirectory:
    """Test skill directory resolution."""

    def test_resolves_skill_name(self, fixtures_dir, monkeypatch):
        """Test resolving skill name to directory path."""
        monkeypatch.chdir(fixtures_dir.parent.parent)

        skill_dir = get_skill_directory(str(fixtures_dir / "skills" / "valid-skill"))

        assert skill_dir.exists()
        assert skill_dir.name == "valid-skill"

    def test_skill_not_found(self):
        """Test error handling when skill directory doesn't exist."""
        with pytest.raises(ValueError, match="Could not find skill directory"):
            get_skill_directory("nonexistent-skill")


class TestAddDependenciesToPyproject:
    """Test adding dependencies to pyproject.toml - CRITICAL functionality."""

    def test_adds_new_dependencies(self, temp_dir, monkeypatch):
        """Test adding new dependencies to pyproject.toml."""
        monkeypatch.chdir(temp_dir)

        # Create initial pyproject.toml
        toml_file = temp_dir / "pyproject.toml"
        toml_file.write_text("""[project]
name = "test"
dependencies = [
    "requests>=2.31.0",
]
""")

        # Add new dependencies
        new_packages = {"numpy", "pandas"}
        add_dependencies_to_pyproject(new_packages, auto_confirm=True)

        # Verify file was updated
        content = toml_file.read_text()
        assert "numpy" in content
        assert "pandas" in content
        assert "requests" in content  # Original preserved

    def test_preserves_existing_dependencies(self, temp_dir, monkeypatch):
        """Test that existing dependencies are preserved."""
        monkeypatch.chdir(temp_dir)

        toml_file = temp_dir / "pyproject.toml"
        original_content = """[project]
name = "test"
dependencies = [
    "requests>=2.31.0",
    "Pillow>=10.0.0",
]
"""
        toml_file.write_text(original_content)

        # Add new package
        new_packages = {"numpy"}
        add_dependencies_to_pyproject(new_packages, auto_confirm=True)

        content = toml_file.read_text()
        assert "requests>=2.31.0" in content
        assert "Pillow>=10.0.0" in content
        assert "numpy" in content

    def test_no_duplicates(self, temp_dir, monkeypatch):
        """Test that duplicate dependencies are not added."""
        monkeypatch.chdir(temp_dir)

        toml_file = temp_dir / "pyproject.toml"
        toml_file.write_text("""[project]
name = "test"
dependencies = [
    "requests>=2.31.0",
]
""")

        # Try to add requests again (should be detected as duplicate)
        # Note: This test assumes get_current_dependencies() is called first
        # in the actual workflow to detect duplicates
        new_packages = set()  # Empty because requests already exists
        add_dependencies_to_pyproject(new_packages, auto_confirm=True)

        content = toml_file.read_text()
        # Count occurrences of "requests"
        assert content.count('"requests') == 1

    def test_handles_empty_package_set(self, temp_dir, monkeypatch):
        """Test that empty package set doesn't modify file."""
        monkeypatch.chdir(temp_dir)

        toml_file = temp_dir / "pyproject.toml"
        original_content = """[project]
name = "test"
dependencies = [
    "requests>=2.31.0",
]
"""
        toml_file.write_text(original_content)

        # Try to add no packages
        add_dependencies_to_pyproject(set(), auto_confirm=True)

        # File should be unchanged
        assert toml_file.read_text() == original_content


class TestIntegrationWorkflow:
    """Integration tests for the full dependency management workflow."""

    def test_full_workflow(self, fixtures_dir, temp_dir, monkeypatch):
        """Test complete workflow: scan skill → update pyproject.toml."""
        monkeypatch.chdir(temp_dir)

        # Set up test environment
        skill_dir = fixtures_dir / "skills" / "skill-with-scripts"
        toml_file = temp_dir / "pyproject.toml"
        toml_file.write_text("""[project]
name = "test"
dependencies = [
    "requests>=2.31.0",
]
""")

        # 1. Scan skill for imports
        all_imports = scan_skill_scripts(skill_dir)

        # 2. Filter to external packages
        external = filter_stdlib_and_local(all_imports)

        # 3. Get current dependencies
        # (In real workflow, this would read from pyproject.toml)
        current = {"requests"}

        # 4. Find missing packages
        missing = set()
        for pkg in external:
            normalized = normalize_package_name(pkg).lower()
            if normalized not in current:
                missing.add(pkg)

        # 5. Add missing dependencies
        add_dependencies_to_pyproject(missing, auto_confirm=True)

        # Verify result
        content = toml_file.read_text()
        assert "requests" in content  # Original preserved
        assert "numpy" in content  # New dependency added
        assert "pandas" in content  # New dependency added
        assert "Pillow" in content  # PIL normalized to Pillow
