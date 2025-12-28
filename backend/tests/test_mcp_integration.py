#!/usr/bin/env python3
"""
Integration tests for MCP tools.

Tests end-to-end workflows through the actual MCP API.
"""
import json
import os
from pathlib import Path

import pytest
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient
from fastmcp import FastMCP

from api.config import settings
from api.supabase_jwt import SupabaseJWTValidator, JWTValidationError
from api.mcp.tools import register_mcp_tools
from tests.test_mcp_client import SyncMCPClient


@pytest.fixture(scope="session")
def bearer_token():
    """Get bearer token from environment."""
    return os.getenv("BEARER_TOKEN", "test-token")


@pytest.fixture(scope="session")
def mcp_http_client():
    mcp = FastMCP("sidebar-tests")
    register_mcp_tools(mcp)
    mcp_app = mcp.http_app()

    test_app = FastAPI(lifespan=mcp_app.lifespan)

    @test_app.middleware("http")
    async def auth_middleware(request: Request, call_next):
        if request.url.path == "/api/health":
            return await call_next(request)

        if settings.auth_dev_mode:
            return await call_next(request)

        auth_header = request.headers.get("Authorization")
        if not auth_header:
            return JSONResponse(
                status_code=401,
                content={"error": "Missing Authorization header"},
                headers={"WWW-Authenticate": "Bearer"},
            )

        try:
            scheme, token = auth_header.split()
            if scheme.lower() != "bearer":
                raise ValueError("Invalid scheme")
            validator = SupabaseJWTValidator()
            await validator.validate_token(token)
        except (ValueError, AttributeError, JWTValidationError):
            return JSONResponse(
                status_code=401,
                content={"error": "Invalid Authorization header"},
                headers={"WWW-Authenticate": "Bearer"},
            )

        return await call_next(request)

    test_app.mount("", mcp_app)

    with TestClient(test_app) as client:
        yield client


@pytest.fixture(scope="session")
def mcp_client(mcp_http_client, bearer_token):
    client = SyncMCPClient(mcp_http_client, bearer_token)
    try:
        client.initialize_session()
    except Exception:
        pass
    return client


def _assert_success(data):
    if not data.get("success"):
        pytest.fail(f"Tool failed: {data}")
    return data




class TestFilesystemOperations:
    """Test filesystem MCP tools end-to-end."""

    def test_fs_list_basic(self, mcp_client):
        """Test listing files in workspace."""
        result = mcp_client.call_tool("fs_list", {
            "path": ".",
            "pattern": "*"
        })

        if result["result"]["isError"]:
            pytest.fail(f"fs_list failed: {result}")
        assert result["result"]["isError"] is False
        content = result["result"]["content"][0]["text"]
        data = json.loads(content)

        _assert_success(data)
        assert "data" in data
        assert "files" in data["data"]
        assert isinstance(data["data"]["files"], list)

    def test_fs_write_and_read(self, mcp_client):
        """Test writing and reading a file."""
        # Write a test file
        test_content = "# Test Document\n\nThis is a test file."
        write_result = mcp_client.call_tool("fs_write", {
            "path": "documents/test-integration.md",
            "content": test_content
        })

        content = write_result["result"]["content"][0]["text"]
        write_data = json.loads(content)
        _assert_success(write_data)

        # Read it back
        read_result = mcp_client.call_tool("fs_read", {
            "path": "documents/test-integration.md"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)

        _assert_success(read_data)
        assert test_content in read_data["data"]["content"]

    def test_fs_copy(self, mcp_client):
        """Test copying a file."""

        # Cleanup any existing test files
        try:
            mcp_client.call_tool("fs_delete", {"path": "documents/copy.txt"})
        except:
            pass

        # Create source file
        write_result = mcp_client.call_tool("fs_write", {
            "path": "documents/source.txt",
            "content": "Source content"
        })
        write_content = write_result["result"]["content"][0]["text"]
        write_data = json.loads(write_content)
        _assert_success(write_data)

        # Copy it
        copy_result = mcp_client.call_tool("fs_copy", {
            "source": "documents/source.txt",
            "destination": "documents/copy.txt"
        })

        content = copy_result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)

        # Verify copy exists and has same content
        read_result = mcp_client.call_tool("fs_read", {
            "path": "documents/copy.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        _assert_success(read_data)
        assert "Source content" in read_data["data"]["content"]

    def test_fs_rename(self, mcp_client):
        """Test renaming a file."""

        # Cleanup any existing test files
        try:
            mcp_client.call_tool("fs_delete", {"path": "documents/old-name.txt"})
        except:
            pass
        try:
            mcp_client.call_tool("fs_delete", {"path": "documents/new-name.txt"})
        except:
            pass

        # Create a file to rename
        write_result = mcp_client.call_tool("fs_write", {
            "path": "documents/old-name.txt",
            "content": "Content to rename"
        })
        write_content = write_result["result"]["content"][0]["text"]
        write_data = json.loads(write_content)
        _assert_success(write_data)
        read_check = mcp_client.call_tool("fs_read", {
            "path": "documents/old-name.txt"
        })
        read_check_content = read_check["result"]["content"][0]["text"]
        read_check_data = json.loads(read_check_content)
        _assert_success(read_check_data)

        # Rename it
        rename_result = mcp_client.call_tool("fs_rename", {
            "path": "documents/old-name.txt",
            "new_name": "new-name.txt"
        })

        content = rename_result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)

        # Verify new name exists
        read_result = mcp_client.call_tool("fs_read", {
            "path": "documents/new-name.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        _assert_success(read_data)

    def test_fs_move(self, mcp_client):
        """Test moving a file to a different directory."""

        # Cleanup any existing test files
        try:
            mcp_client.call_tool("fs_delete", {"path": "documents/to-move.txt"})
        except:
            pass
        try:
            mcp_client.call_tool("fs_delete", {"path": "notes/moved-file.txt"})
        except:
            pass

        # Create source file
        write_result = mcp_client.call_tool("fs_write", {
            "path": "documents/to-move.txt",
            "content": "Moving this file"
        })
        write_content = write_result["result"]["content"][0]["text"]
        write_data = json.loads(write_content)
        _assert_success(write_data)

        # Move it to notes
        move_result = mcp_client.call_tool("fs_move", {
            "source": "documents/to-move.txt",
            "destination": "notes/moved-file.txt"
        })

        content = move_result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)

        # Verify file is in new location
        read_result = mcp_client.call_tool("fs_read", {
            "path": "notes/moved-file.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        assert "Moving this file" in read_data["data"]["content"]

    def test_fs_search_by_name(self, mcp_client):
        """Test searching files by name pattern."""

        # Create some test files
        mcp_client.call_tool("fs_write", {
            "path": "documents/search-test-1.md",
            "content": "Test content 1"
        })
        mcp_client.call_tool("fs_write", {
            "path": "documents/search-test-2.md",
            "content": "Test content 2"
        })
        mcp_client.call_tool("fs_write", {
            "path": "documents/other-file.txt",
            "content": "Other content"
        })

        # Search for files matching pattern
        search_result = mcp_client.call_tool("fs_search", {
            "directory": "documents",
            "name_pattern": "search-test-*.md"
        })

        content = search_result["result"]["content"][0]["text"]
        data = json.loads(content)

        _assert_success(data)
        assert data["data"]["count"] >= 2
        # Check that results contain our test files
        result_paths = [r["path"] for r in data["data"]["results"]]
        assert any("search-test-1.md" in p for p in result_paths)
        assert any("search-test-2.md" in p for p in result_paths)

    def test_fs_search_by_content(self, mcp_client):
        """Test searching files by content."""

        # Create files with searchable content
        mcp_client.call_tool("fs_write", {
            "path": "documents/content-search-1.txt",
            "content": "This file contains the special keyword FINDME"
        })
        mcp_client.call_tool("fs_write", {
            "path": "documents/content-search-2.txt",
            "content": "This file also has FINDME in it"
        })
        mcp_client.call_tool("fs_write", {
            "path": "documents/content-search-3.txt",
            "content": "This file has nothing special"
        })

        # Search for content
        search_result = mcp_client.call_tool("fs_search", {
            "directory": "documents",
            "content_pattern": "FINDME"
        })

        content = search_result["result"]["content"][0]["text"]
        data = json.loads(content)

        _assert_success(data)
        assert data["data"]["count"] >= 2
        # Verify search found files with the keyword
        for result in data["data"]["results"]:
            assert result["match_type"] == "content"
            assert result["match_count"] >= 1

    def test_fs_delete(self, mcp_client):
        """Test deleting a file."""

        # Create a file to delete
        mcp_client.call_tool("fs_write", {
            "path": "documents/to-delete.txt",
            "content": "This will be deleted"
        })

        # Delete it
        delete_result = mcp_client.call_tool("fs_delete", {
            "path": "documents/to-delete.txt"
        })

        content = delete_result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)

    def test_dry_run_operations(self, mcp_client):
        """Test dry-run mode for destructive operations."""

        # Create a test file
        mcp_client.call_tool("fs_write", {
            "path": "documents/dry-run-test.txt",
            "content": "Testing dry run"
        })

        # Try to delete with dry-run
        delete_result = mcp_client.call_tool("fs_delete", {
            "path": "documents/dry-run-test.txt",
            "dry_run": True
        })

        content = delete_result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)
        assert data["dry_run"] is True

        # Verify file still exists
        read_result = mcp_client.call_tool("fs_read", {
            "path": "documents/dry-run-test.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        _assert_success(read_data)  # File should still exist


class TestNotesOperations:
    """Test notes MCP tools end-to-end."""

    def test_notes_create(self, mcp_client):
        """Test creating a new note."""

        result = mcp_client.call_tool("notes_create", {
            "title": "Integration Test Note",
            "content": "This is a test note created during integration testing.",
            "tags": ["test", "integration"]
        })

        content = result["result"]["content"][0]["text"]
        data = json.loads(content)

        _assert_success(data)
        assert "id" in data["data"]
        assert data["data"]["title"] == "Integration Test Note"

    def test_notes_update(self, mcp_client):
        """Test updating an existing note."""

        # Create a note first
        create_result = mcp_client.call_tool("notes_create", {
            "title": "Update Test Note",
            "content": "Original content"
        })
        create_content = create_result["result"]["content"][0]["text"]
        create_data = json.loads(create_content)
        _assert_success(create_data)

        # Update it
        result = mcp_client.call_tool("notes_update", {
            "title": "Update Test Note",
            "content": "Updated content"
        })

        content = result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)

    def test_notes_append(self, mcp_client):
        """Test appending to an existing note."""

        # Create a note
        create_result = mcp_client.call_tool("notes_create", {
            "title": "Append Test Note",
            "content": "Initial content"
        })
        create_content = create_result["result"]["content"][0]["text"]
        create_data = json.loads(create_content)
        _assert_success(create_data)

        # Append to it
        result = mcp_client.call_tool("notes_append", {
            "title": "Append Test Note",
            "content": "\n\nAppended content"
        })

        content = result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)


class TestSecurityAndValidation:
    """Test security features and validation."""

    def test_path_traversal_rejected(self, mcp_client):
        """Test that path traversal attempts are rejected."""

        # Try to read outside workspace
        result = mcp_client.call_tool("fs_read", {
            "path": "../../../etc/passwd"
        })

        content = result["result"]["content"][0]["text"]

        # Error might be plain text or JSON
        try:
            data = json.loads(content)
            assert data["success"] is False
            assert "traversal" in data["error"].lower()
        except json.JSONDecodeError:
            # Error returned as plain text
            assert "traversal" in content.lower() or "Path traversal" in content

    def test_write_to_non_writable_path_rejected(self, mcp_client):
        """Test that writes to non-allowlisted paths are rejected."""

        # Try to write to workspace root (not in allowlist)
        result = mcp_client.call_tool("fs_write", {
            "path": "forbidden.txt",
            "content": "This should fail"
        })

        content = result["result"]["content"][0]["text"]

        # Error might be plain text or JSON
        try:
            data = json.loads(content)
            assert data["success"] is False
            assert "not writable" in data["error"].lower() or "allowlist" in data["error"].lower()
        except json.JSONDecodeError:
            # Error returned as plain text
            assert "not writable" in content.lower() or "allowlist" in content.lower()


class TestComplexWorkflows:
    """Test complex multi-step workflows."""

    def test_document_workflow(self, mcp_client):
        """Test a complete document workflow."""

        # 1. Create a document
        mcp_client.call_tool("fs_write", {
            "path": "documents/workflow-test.md",
            "content": "# Workflow Test\n\nInitial version"
        })

        # 2. Copy it as a backup
        copy_result = mcp_client.call_tool("fs_copy", {
            "source": "documents/workflow-test.md",
            "destination": "documents/workflow-test-backup.md"
        })
        copy_content = copy_result["result"]["content"][0]["text"]
        copy_data = json.loads(copy_content)
        _assert_success(copy_data)

        # 3. Update the original
        write_result = mcp_client.call_tool("fs_write", {
            "path": "documents/workflow-test.md",
            "content": "# Workflow Test\n\nUpdated version"
        })
        write_content = write_result["result"]["content"][0]["text"]
        write_data = json.loads(write_content)
        _assert_success(write_data)

        # 4. Search to find both versions
        search_result = mcp_client.call_tool("fs_search", {
            "directory": "documents",
            "name_pattern": "workflow-test*.md"
        })

        content = search_result["result"]["content"][0]["text"]
        data = json.loads(content)
        _assert_success(data)
        assert data["data"]["count"] >= 2

        # 5. Clean up - delete the backup
        delete_result = mcp_client.call_tool("fs_delete", {
            "path": "documents/workflow-test-backup.md"
        })
        delete_content = delete_result["result"]["content"][0]["text"]
        delete_data = json.loads(delete_content)
        _assert_success(delete_data)

        # Verify workflow completed successfully
        _assert_success(data)


def main():
    """Run integration tests manually."""
    pytest.main([__file__, "-v", "-o", "addopts="])


if __name__ == "__main__":
    main()
