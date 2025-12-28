#!/usr/bin/env python3
"""
Integration tests for MCP tools.

Tests end-to-end workflows through the actual MCP API.
"""
import pytest
import asyncio
import os
from pathlib import Path
from tests.test_mcp_client import MCPClient


@pytest.fixture
def bearer_token():
    """Get bearer token from environment."""
    token = os.getenv("BEARER_TOKEN")
    if not token:
        pytest.skip("BEARER_TOKEN not set in environment")
    return token


@pytest.fixture
def base_url():
    """Get base URL for API."""
    url = os.getenv("MCP_BASE_URL")
    if not url:
        pytest.skip("MCP_BASE_URL not set; skipping MCP integration tests.")
    return url


async def get_initialized_client(base_url: str, bearer_token: str):
    """Create and initialize an MCP client."""
    client = MCPClient(base_url, bearer_token)
    try:
        await client.initialize_session()
    except Exception:
        # Continue if session init not required
        pass
    return client


@pytest.mark.asyncio
class TestFilesystemOperations:
    """Test filesystem MCP tools end-to-end."""

    async def test_fs_list_basic(self, base_url, bearer_token):
        """Test listing files in workspace."""
        client = await get_initialized_client(base_url, bearer_token)
        result = await client.call_tool("fs_list", {
            "path": ".",
            "pattern": "*"
        })

        assert result["result"]["isError"] is False
        content = result["result"]["content"][0]["text"]
        import json
        data = json.loads(content)

        assert data["success"] is True
        assert "data" in data
        assert "files" in data["data"]
        assert isinstance(data["data"]["files"], list)

    async def test_fs_write_and_read(self, base_url, bearer_token):
        """Test writing and reading a file."""
        client = await get_initialized_client(base_url, bearer_token)
        # Write a test file
        test_content = "# Test Document\n\nThis is a test file."
        write_result = await client.call_tool("fs_write", {
            "path": "documents/test-integration.md",
            "content": test_content
        })

        content = write_result["result"]["content"][0]["text"]
        import json
        write_data = json.loads(content)
        assert write_data["success"] is True

        # Read it back
        read_result = await client.call_tool("fs_read", {
            "path": "documents/test-integration.md"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)

        assert read_data["success"] is True
        assert test_content in read_data["data"]["content"]

    async def test_fs_copy(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test copying a file."""
        import json

        # Cleanup any existing test files
        try:
            await client.call_tool("fs_delete", {"path": "documents/copy.txt"})
        except:
            pass

        # Create source file
        await client.call_tool("fs_write", {
            "path": "documents/source.txt",
            "content": "Source content"
        })

        # Copy it
        copy_result = await client.call_tool("fs_copy", {
            "source": "documents/source.txt",
            "destination": "documents/copy.txt"
        })

        content = copy_result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["success"] is True

        # Verify copy exists and has same content
        read_result = await client.call_tool("fs_read", {
            "path": "documents/copy.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        assert "Source content" in read_data["data"]["content"]

    async def test_fs_rename(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test renaming a file."""
        import json

        # Cleanup any existing test files
        try:
            await client.call_tool("fs_delete", {"path": "documents/old-name.txt"})
        except:
            pass
        try:
            await client.call_tool("fs_delete", {"path": "documents/new-name.txt"})
        except:
            pass

        # Create a file to rename
        await client.call_tool("fs_write", {
            "path": "documents/old-name.txt",
            "content": "Content to rename"
        })

        # Rename it
        rename_result = await client.call_tool("fs_rename", {
            "path": "documents/old-name.txt",
            "new_name": "new-name.txt"
        })

        content = rename_result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["success"] is True

        # Verify new name exists
        read_result = await client.call_tool("fs_read", {
            "path": "documents/new-name.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        assert read_data["success"] is True

    async def test_fs_move(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test moving a file to a different directory."""
        import json

        # Cleanup any existing test files
        try:
            await client.call_tool("fs_delete", {"path": "documents/to-move.txt"})
        except:
            pass
        try:
            await client.call_tool("fs_delete", {"path": "notes/moved-file.txt"})
        except:
            pass

        # Create source file
        await client.call_tool("fs_write", {
            "path": "documents/to-move.txt",
            "content": "Moving this file"
        })

        # Move it to notes
        move_result = await client.call_tool("fs_move", {
            "source": "documents/to-move.txt",
            "destination": "notes/moved-file.txt"
        })

        content = move_result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["success"] is True

        # Verify file is in new location
        read_result = await client.call_tool("fs_read", {
            "path": "notes/moved-file.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        assert "Moving this file" in read_data["data"]["content"]

    async def test_fs_search_by_name(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test searching files by name pattern."""
        import json

        # Create some test files
        await client.call_tool("fs_write", {
            "path": "documents/search-test-1.md",
            "content": "Test content 1"
        })
        await client.call_tool("fs_write", {
            "path": "documents/search-test-2.md",
            "content": "Test content 2"
        })
        await client.call_tool("fs_write", {
            "path": "documents/other-file.txt",
            "content": "Other content"
        })

        # Search for files matching pattern
        search_result = await client.call_tool("fs_search", {
            "directory": "documents",
            "name_pattern": "search-test-*.md"
        })

        content = search_result["result"]["content"][0]["text"]
        data = json.loads(content)

        assert data["success"] is True
        assert data["data"]["count"] >= 2
        # Check that results contain our test files
        result_paths = [r["path"] for r in data["data"]["results"]]
        assert any("search-test-1.md" in p for p in result_paths)
        assert any("search-test-2.md" in p for p in result_paths)

    async def test_fs_search_by_content(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test searching files by content."""
        import json

        # Create files with searchable content
        await client.call_tool("fs_write", {
            "path": "documents/content-search-1.txt",
            "content": "This file contains the special keyword FINDME"
        })
        await client.call_tool("fs_write", {
            "path": "documents/content-search-2.txt",
            "content": "This file also has FINDME in it"
        })
        await client.call_tool("fs_write", {
            "path": "documents/content-search-3.txt",
            "content": "This file has nothing special"
        })

        # Search for content
        search_result = await client.call_tool("fs_search", {
            "directory": "documents",
            "content_pattern": "FINDME"
        })

        content = search_result["result"]["content"][0]["text"]
        data = json.loads(content)

        assert data["success"] is True
        assert data["data"]["count"] >= 2
        # Verify search found files with the keyword
        for result in data["data"]["results"]:
            assert result["match_type"] == "content"
            assert result["match_count"] >= 1

    async def test_fs_delete(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test deleting a file."""
        import json

        # Create a file to delete
        await client.call_tool("fs_write", {
            "path": "documents/to-delete.txt",
            "content": "This will be deleted"
        })

        # Delete it
        delete_result = await client.call_tool("fs_delete", {
            "path": "documents/to-delete.txt"
        })

        content = delete_result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["success"] is True

    async def test_dry_run_operations(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test dry-run mode for destructive operations."""
        import json

        # Create a test file
        await client.call_tool("fs_write", {
            "path": "documents/dry-run-test.txt",
            "content": "Testing dry run"
        })

        # Try to delete with dry-run
        delete_result = await client.call_tool("fs_delete", {
            "path": "documents/dry-run-test.txt",
            "dry_run": True
        })

        content = delete_result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["success"] is True
        assert data["dry_run"] is True

        # Verify file still exists
        read_result = await client.call_tool("fs_read", {
            "path": "documents/dry-run-test.txt"
        })

        read_content = read_result["result"]["content"][0]["text"]
        read_data = json.loads(read_content)
        assert read_data["success"] is True  # File should still exist


@pytest.mark.asyncio
class TestNotesOperations:
    """Test notes MCP tools end-to-end."""

    async def test_notes_create(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test creating a new note."""
        import json

        result = await client.call_tool("notes_create", {
            "title": "Integration Test Note",
            "content": "This is a test note created during integration testing.",
            "tags": ["test", "integration"]
        })

        content = result["result"]["content"][0]["text"]
        data = json.loads(content)

        assert data["success"] is True
        assert "path" in data["data"]
        assert "integration-test-note.md" in data["data"]["path"]

    async def test_notes_update(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test updating an existing note."""
        import json

        # Create a note first
        await client.call_tool("notes_create", {
            "title": "Update Test Note",
            "content": "Original content"
        })

        # Update it
        result = await client.call_tool("notes_update", {
            "title": "Update Test Note",
            "content": "Updated content"
        })

        content = result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["success"] is True

    async def test_notes_append(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test appending to an existing note."""
        import json

        # Create a note
        await client.call_tool("notes_create", {
            "title": "Append Test Note",
            "content": "Initial content"
        })

        # Append to it
        result = await client.call_tool("notes_append", {
            "title": "Append Test Note",
            "content": "\n\nAppended content"
        })

        content = result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["success"] is True


@pytest.mark.asyncio
class TestSecurityAndValidation:
    """Test security features and validation."""

    async def test_path_traversal_rejected(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test that path traversal attempts are rejected."""
        import json

        # Try to read outside workspace
        result = await client.call_tool("fs_read", {
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

    async def test_write_to_non_writable_path_rejected(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test that writes to non-allowlisted paths are rejected."""
        import json

        # Try to write to workspace root (not in allowlist)
        result = await client.call_tool("fs_write", {
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


@pytest.mark.asyncio
class TestComplexWorkflows:
    """Test complex multi-step workflows."""

    async def test_document_workflow(self, base_url, bearer_token):
        client = await get_initialized_client(base_url, bearer_token)
        """Test a complete document workflow."""
        import json

        # 1. Create a document
        await client.call_tool("fs_write", {
            "path": "documents/workflow-test.md",
            "content": "# Workflow Test\n\nInitial version"
        })

        # 2. Copy it as a backup
        await client.call_tool("fs_copy", {
            "source": "documents/workflow-test.md",
            "destination": "documents/workflow-test-backup.md"
        })

        # 3. Update the original
        await client.call_tool("fs_write", {
            "path": "documents/workflow-test.md",
            "content": "# Workflow Test\n\nUpdated version"
        })

        # 4. Search to find both versions
        search_result = await client.call_tool("fs_search", {
            "directory": "documents",
            "name_pattern": "workflow-test*.md"
        })

        content = search_result["result"]["content"][0]["text"]
        data = json.loads(content)
        assert data["data"]["count"] >= 2

        # 5. Clean up - delete the backup
        await client.call_tool("fs_delete", {
            "path": "documents/workflow-test-backup.md"
        })

        # Verify workflow completed successfully
        assert data["success"] is True


def main():
    """Run integration tests manually."""
    pytest.main([__file__, "-v", "-o", "addopts="])


if __name__ == "__main__":
    main()
