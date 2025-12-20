"""MCP tool definitions with semantic parameters (not CLI-style)."""
from fastmcp import FastMCP
from api.config import settings
from api.executors.skill_executor import SkillExecutor
from api.security.path_validator import PathValidator
from api.security.audit_logger import AuditLogger
import json
import time

# Initialize executor and path validator
executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
path_validator = PathValidator(settings.workspace_base, settings.writable_paths)


def register_mcp_tools(mcp: FastMCP):
    """Register all MCP tools with semantic parameters."""

    @mcp.tool()
    async def fs_list(
        path: str = ".",
        pattern: str = "*",
        recursive: bool = False
    ) -> str:
        """List files in workspace directory.

        Args:
            path: Directory path relative to workspace (default: ".")
            pattern: Glob pattern to filter files (default: "*")
            recursive: List files recursively (default: false)
        """
        start_time = time.time()

        # Validate path
        validated_path = path_validator.validate_read_path(path)

        # Execute via skill script
        args = [path, "--pattern", pattern]
        if recursive:
            args.append("--recursive")

        result = await executor.execute("fs", "list.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_list",
            parameters={"path": path, "pattern": pattern, "recursive": recursive},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_read(
        path: str,
        start_line: int = None,
        end_line: int = None
    ) -> str:
        """Read file content from workspace.

        Args:
            path: File path relative to workspace
            start_line: Optional starting line number (1-indexed)
            end_line: Optional ending line number (inclusive)
        """
        start_time = time.time()

        # Validate path
        validated_path = path_validator.validate_read_path(path)

        # Build args - semantic params mapped to script options
        args = [path]
        if start_line and end_line:
            num_lines = end_line - start_line + 1
            args.extend(["--offset", str(start_line - 1), "--lines", str(num_lines)])
        elif end_line:
            args.extend(["--lines", str(end_line)])

        result = await executor.execute("fs", "read.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_read",
            parameters={"path": path, "start_line": start_line, "end_line": end_line},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_write(
        path: str,
        content: str,
        dry_run: bool = False
    ) -> str:
        """Write content to file in workspace.

        Args:
            path: File path relative to workspace
            content: Content to write (replaces existing)
            dry_run: If true, validate but don't actually write
        """
        start_time = time.time()

        # Validate write path (enforces allowlist)
        validated_path = path_validator.validate_write_path(path)

        if dry_run:
            # Audit log dry-run
            AuditLogger.log_tool_call(
                tool_name="fs_write",
                parameters={"path": path, "dry_run": True},
                resolved_path=validated_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would write {len(content)} bytes to {path}"
            })

        # Execute write
        args = [path, "--content", content, "--mode", "replace"]
        result = await executor.execute("fs", "write.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_write",
            parameters={"path": path, "content_length": len(content)},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_delete(
        path: str,
        dry_run: bool = False
    ) -> str:
        """Delete file or directory from workspace.

        Args:
            path: File/directory path relative to workspace
            dry_run: If true, validate but don't actually delete
        """
        start_time = time.time()

        # Validate write path (delete is a write operation)
        validated_path = path_validator.validate_write_path(path)

        if dry_run:
            # Audit log dry-run
            AuditLogger.log_tool_call(
                tool_name="fs_delete",
                parameters={"path": path, "dry_run": True},
                resolved_path=validated_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would delete {path}"
            })

        # Execute delete
        args = [path]
        result = await executor.execute("fs", "delete.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_delete",
            parameters={"path": path},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def notes_create(
        title: str,
        content: str,
        folder: str = None,
        tags: list[str] = None
    ) -> str:
        """Create a new markdown note with metadata.

        Args:
            title: Note title
            content: Note content (markdown)
            folder: Optional subfolder in notes/ (default: YYYY/Month)
            tags: Optional list of tags
        """
        start_time = time.time()

        # Build args
        args = [title, "--content", content, "--mode", "create"]
        if folder:
            args.extend(["--folder", folder])
        if tags:
            args.extend(["--tags", ",".join(tags)])

        result = await executor.execute("notes", "save_markdown.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="notes_create",
            parameters={"title": title, "folder": folder, "tags": tags},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def notes_update(
        title: str,
        content: str,
        folder: str = None
    ) -> str:
        """Update existing note (replace content).

        Args:
            title: Note title (identifies existing note)
            content: New content (replaces existing)
            folder: Optional subfolder to search in
        """
        start_time = time.time()

        args = [title, "--content", content, "--mode", "update"]
        if folder:
            args.extend(["--folder", folder])

        result = await executor.execute("notes", "save_markdown.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="notes_update",
            parameters={"title": title, "folder": folder},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def notes_append(
        title: str,
        content: str,
        folder: str = None
    ) -> str:
        """Append content to existing note.

        Args:
            title: Note title (identifies existing note)
            content: Content to append
            folder: Optional subfolder to search in
        """
        start_time = time.time()

        args = [title, "--content", content, "--mode", "append"]
        if folder:
            args.extend(["--folder", folder])

        result = await executor.execute("notes", "save_markdown.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="notes_append",
            parameters={"title": title, "folder": folder},
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)
