"""Tests for PathValidator security."""

from pathlib import Path

import pytest
from api.security.path_validator import PathValidator
from fastapi import HTTPException


@pytest.fixture
def temp_workspace(tmp_path):
    """Create a temporary workspace for testing."""
    workspace = tmp_path / "workspace"
    workspace.mkdir()

    # Create writable directories
    notes_dir = workspace / "notes"
    notes_dir.mkdir()
    docs_dir = workspace / "documents"
    docs_dir.mkdir()

    # Create some test files
    (notes_dir / "test.md").write_text("# Test Note")
    (workspace / "readme.txt").write_text("Read-only file")

    return workspace


@pytest.fixture
def validator(temp_workspace):
    """Create a PathValidator for testing."""
    writable_paths = [str(temp_workspace / "notes"), str(temp_workspace / "documents")]
    return PathValidator(temp_workspace, writable_paths)


class TestPathValidatorRead:
    """Test read path validation."""

    def test_validate_read_relative_path(self, validator, temp_workspace):
        """Should accept relative paths within workspace."""
        result = validator.validate_read_path("notes/test.md")
        assert result == temp_workspace / "notes" / "test.md"

    def test_validate_read_dot_path(self, validator, temp_workspace):
        """Should accept current directory."""
        result = validator.validate_read_path(".")
        assert result == temp_workspace

    def test_validate_read_rejects_traversal(self, validator):
        """Should reject path traversal attempts."""
        with pytest.raises(HTTPException) as exc_info:
            validator.validate_read_path("../etc/passwd")
        assert exc_info.value.status_code == 400
        assert "Path traversal not allowed" in str(exc_info.value.detail)

    def test_validate_read_rejects_absolute_outside_workspace(self, validator):
        """Should reject absolute paths outside workspace."""
        with pytest.raises(HTTPException) as exc_info:
            validator.validate_read_path("/etc/passwd")
        assert exc_info.value.status_code == 403
        assert "Path outside workspace" in str(exc_info.value.detail)

    def test_validate_read_accepts_absolute_in_workspace(
        self, validator, temp_workspace
    ):
        """Should accept absolute paths within workspace."""
        abs_path = str(temp_workspace / "notes" / "test.md")
        result = validator.validate_read_path(abs_path)
        assert result == temp_workspace / "notes" / "test.md"


class TestPathValidatorWrite:
    """Test write path validation."""

    def test_validate_write_allowed_path(self, validator, temp_workspace):
        """Should accept writes to allowlisted paths."""
        result = validator.validate_write_path("notes/new-note.md")
        assert result == temp_workspace / "notes" / "new-note.md"

    def test_validate_write_rejects_non_writable(self, validator):
        """Should reject writes outside allowlist."""
        with pytest.raises(HTTPException) as exc_info:
            validator.validate_write_path("readme.txt")
        assert exc_info.value.status_code == 403
        assert "not writable" in str(exc_info.value.detail)

    def test_validate_write_rejects_traversal(self, validator):
        """Should reject path traversal in writes."""
        with pytest.raises(HTTPException) as exc_info:
            validator.validate_write_path("notes/../../etc/passwd")
        assert exc_info.value.status_code == 400
        assert "Path traversal not allowed" in str(exc_info.value.detail)

    def test_validate_write_documents_folder(self, validator, temp_workspace):
        """Should allow writes to documents/ folder."""
        result = validator.validate_write_path("documents/report.pdf")
        assert result == temp_workspace / "documents" / "report.pdf"

    def test_validate_write_nested_path(self, validator, temp_workspace):
        """Should allow nested paths within writable directories."""
        result = validator.validate_write_path("notes/2025/january/note.md")
        assert result == temp_workspace / "notes" / "2025" / "january" / "note.md"


class TestPathValidatorSymlinks:
    """Test symlink protection."""

    @pytest.mark.skipif(
        not hasattr(Path, "symlink_to"), reason="Symlink support not available"
    )
    def test_validate_rejects_symlinks(self, validator, temp_workspace, tmp_path):
        """Should reject symlink attempts to escape workspace."""
        # Create a symlink pointing outside workspace
        external_dir = tmp_path / "external"
        external_dir.mkdir()

        symlink_path = temp_workspace / "notes" / "escape"
        try:
            symlink_path.symlink_to(external_dir)

            # Should reject the symlink (either 400 for symlink or 403 for outside workspace)
            with pytest.raises(HTTPException) as exc_info:
                validator.validate_read_path("notes/escape")
            assert exc_info.value.status_code in [400, 403]
            # Error message varies based on whether symlink check or path check happens first
        except OSError:
            # Skip if symlinks not supported (Windows without admin)
            pytest.skip("Symlink creation not supported")


class TestPathValidatorEdgeCases:
    """Test edge cases and security scenarios."""

    def test_validate_empty_path(self, validator, temp_workspace):
        """Should handle empty path as current directory."""
        result = validator.validate_read_path("")
        assert result == temp_workspace

    def test_validate_multiple_dots(self, validator):
        """Should reject multiple dot sequences."""
        with pytest.raises(HTTPException):
            validator.validate_read_path("notes/../../../../../../etc/passwd")

    def test_validate_hidden_traversal(self, validator):
        """Should catch obfuscated traversal attempts."""
        traversal_attempts = [
            "notes/../../../etc/passwd",
            "notes/./../../etc/passwd",
            "../tmp/skills/notes/test.md",  # Trying to go up then back
        ]

        for attempt in traversal_attempts:
            with pytest.raises(HTTPException) as exc_info:
                validator.validate_read_path(attempt)
            assert exc_info.value.status_code in [400, 403]

    def test_get_relative_path(self, validator, temp_workspace):
        """Should convert absolute path back to relative."""
        abs_path = temp_workspace / "notes" / "test.md"
        relative = validator.get_relative_path(abs_path)
        assert relative == "notes/test.md"
