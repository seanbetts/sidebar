"""Notes MCP tool registration."""

from __future__ import annotations

import json
import time

from api.security.audit_logger import AuditLogger


def register_notes_tools(mcp, executor, default_user_id: str) -> None:
    """Register note tools with the MCP server.

    Args:
        mcp: FastMCP instance to register tools on.
        executor: Skill executor used to run scripts.
        default_user_id: Default user ID for tool execution.
    """

    @mcp.tool()
    async def notes_create(
        document: dict,
        folder: str | None = None,
        tags: list[str] | None = None,
    ) -> str:
        """Create a new note.

        Args:
            document: Semantic note document with version and blocks.
            folder: Optional folder path.
            tags: Optional list of tags.
        """
        start_time = time.time()

        args = [
            "--document",
            json.dumps(document),
            "--mode",
            "create",
            "--database",
            "--user-id",
            default_user_id,
        ]
        if folder:
            args.extend(["--folder", folder])
        if tags:
            args.extend(["--tags", ",".join(tags)])

        result = await executor.execute("notes", "save_note_document.py", args)

        AuditLogger.log_tool_call(
            tool_name="notes_create",
            parameters={"document": document, "folder": folder, "tags": tags},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def notes_update(
        document: dict,
        note_id: str,
    ) -> str:
        """Update existing note (replace content)."""
        start_time = time.time()

        args = [
            "--document",
            json.dumps(document),
            "--mode",
            "update",
            "--note-id",
            note_id,
            "--database",
            "--user-id",
            default_user_id,
        ]

        result = await executor.execute("notes", "save_note_document.py", args)

        AuditLogger.log_tool_call(
            tool_name="notes_update",
            parameters={"document": document, "note_id": note_id},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def notes_append(
        document: dict,
        note_id: str,
    ) -> str:
        """Append semantic blocks to an existing note."""
        start_time = time.time()

        args = [
            "--document",
            json.dumps(document),
            "--mode",
            "append",
            "--note-id",
            note_id,
            "--database",
            "--user-id",
            default_user_id,
        ]

        result = await executor.execute("notes", "save_note_document.py", args)

        AuditLogger.log_tool_call(
            tool_name="notes_append",
            parameters={"document": document, "note_id": note_id},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)
