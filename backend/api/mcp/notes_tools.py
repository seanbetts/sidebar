"""Notes MCP tool registration."""
from __future__ import annotations

import json
import time

from api.security.audit_logger import AuditLogger


def register_notes_tools(mcp, executor, default_user_id: str) -> None:
    @mcp.tool()
    async def notes_create(
        title: str,
        content: str,
        folder: str = None,
        tags: list[str] = None,
    ) -> str:
        """Create a new markdown note with metadata."""
        start_time = time.time()

        args = [title, "--content", content, "--mode", "create", "--database", "--user-id", default_user_id]
        if folder:
            args.extend(["--folder", folder])
        if tags:
            args.extend(["--tags", ",".join(tags)])

        result = await executor.execute("notes", "save_markdown.py", args)

        AuditLogger.log_tool_call(
            tool_name="notes_create",
            parameters={"title": title, "folder": folder, "tags": tags},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def notes_update(
        title: str,
        content: str,
        folder: str = None,
        note_id: str = None,
    ) -> str:
        """Update existing note (replace content)."""
        start_time = time.time()

        args = [title, "--content", content, "--mode", "update", "--database", "--user-id", default_user_id]
        if folder:
            args.extend(["--folder", folder])
        if note_id:
            args.extend(["--note-id", note_id])

        result = await executor.execute("notes", "save_markdown.py", args)

        AuditLogger.log_tool_call(
            tool_name="notes_update",
            parameters={"title": title, "folder": folder},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def notes_append(
        title: str,
        content: str,
        folder: str = None,
        note_id: str = None,
    ) -> str:
        """Append content to existing note."""
        start_time = time.time()

        args = [title, "--content", content, "--mode", "append", "--database", "--user-id", default_user_id]
        if folder:
            args.extend(["--folder", folder])
        if note_id:
            args.extend(["--note-id", note_id])

        result = await executor.execute("notes", "save_markdown.py", args)

        AuditLogger.log_tool_call(
            tool_name="notes_append",
            parameters={"title": title, "folder": folder},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)
