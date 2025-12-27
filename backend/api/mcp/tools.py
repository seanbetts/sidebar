"""MCP tool definitions with semantic parameters (not CLI-style)."""
from fastmcp import FastMCP
from api.config import settings
from api.executors.skill_executor import SkillExecutor
from api.db.dependencies import DEFAULT_USER_ID
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
        """List files in storage directory.

        Args:
            path: Directory path relative to storage (default: ".")
            pattern: Glob pattern to filter files (default: "*")
            recursive: List files recursively (default: false)
        """
        start_time = time.time()

        # Validate path
        validated_path = path_validator.validate_read_path(path)

        # Execute via skill script
        args = [path, "--pattern", pattern, "--user-id", DEFAULT_USER_ID]
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
        """Read file content from storage.

        Args:
            path: File path relative to storage
            start_line: Optional starting line number (1-indexed)
            end_line: Optional ending line number (inclusive)
        """
        start_time = time.time()

        # Validate path
        validated_path = path_validator.validate_read_path(path)

        # Build args - semantic params mapped to script options
        args = [path, "--user-id", DEFAULT_USER_ID]
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
        """Write content to file in storage.

        Args:
            path: File path relative to storage
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
        args = [path, "--content", content, "--mode", "replace", "--user-id", DEFAULT_USER_ID]
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
        """Delete file or directory from storage.

        Args:
            path: File/directory path relative to storage
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
        args = [path, "--user-id", DEFAULT_USER_ID]
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
        args = [title, "--content", content, "--mode", "create", "--database", "--user-id", DEFAULT_USER_ID]
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

        args = [title, "--content", content, "--mode", "update", "--database", "--user-id", DEFAULT_USER_ID]
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

        args = [title, "--content", content, "--mode", "append", "--database", "--user-id", DEFAULT_USER_ID]
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

    @mcp.tool()
    async def fs_move(
        source: str,
        destination: str,
        dry_run: bool = False
    ) -> str:
        """Move file or directory to a new location in storage.

        Args:
            source: Source path relative to storage
            destination: Destination path relative to storage
            dry_run: If true, validate but don't actually move
        """
        start_time = time.time()

        # Validate paths
        source_path = path_validator.validate_write_path(source)
        dest_path = path_validator.validate_write_path(destination)

        if dry_run:
            # Audit log dry-run
            AuditLogger.log_tool_call(
                tool_name="fs_move",
                parameters={"source": source, "destination": destination, "dry_run": True},
                resolved_path=source_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would move {source} to {destination}"
            })

        # Execute move
        args = [source, destination]
        result = await executor.execute("fs", "move.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_move",
            parameters={"source": source, "destination": destination},
            resolved_path=source_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_rename(
        path: str,
        new_name: str,
        dry_run: bool = False
    ) -> str:
        """Rename file or directory (stays in same directory).

        Args:
        path: Path to file/directory relative to storage
            new_name: New name (just the name, not a full path)
            dry_run: If true, validate but don't actually rename
        """
        start_time = time.time()

        # Validate path
        validated_path = path_validator.validate_write_path(path)

        if dry_run:
            # Audit log dry-run
            AuditLogger.log_tool_call(
                tool_name="fs_rename",
                parameters={"path": path, "new_name": new_name, "dry_run": True},
                resolved_path=validated_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would rename to {new_name}"
            })

        # Execute rename
        args = [path, new_name]
        result = await executor.execute("fs", "rename.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_rename",
            parameters={"path": path, "new_name": new_name},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_copy(
        source: str,
        destination: str,
        dry_run: bool = False
    ) -> str:
        """Copy file or directory to a new location in storage.

        Args:
            source: Source path relative to storage
            destination: Destination path relative to storage
            dry_run: If true, validate but don't actually copy
        """
        start_time = time.time()

        # Validate paths
        source_path = path_validator.validate_read_path(source)
        dest_path = path_validator.validate_write_path(destination)

        if dry_run:
            # Audit log dry-run
            AuditLogger.log_tool_call(
                tool_name="fs_copy",
                parameters={"source": source, "destination": destination, "dry_run": True},
                resolved_path=source_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would copy {source} to {destination}"
            })

        # Execute copy
        args = [source, destination]
        result = await executor.execute("fs", "copy.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_copy",
            parameters={"source": source, "destination": destination},
            resolved_path=source_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_search(
        directory: str = ".",
        name_pattern: str = None,
        content_pattern: str = None,
        case_sensitive: bool = False,
        max_results: int = 100
    ) -> str:
        """Search for files by name or content in storage.

        Args:
            directory: Directory to search in (default: ".")
            name_pattern: Filename pattern (supports * and ? wildcards)
            content_pattern: Content to search for (regex pattern)
            case_sensitive: Make search case-sensitive (default: false)
            max_results: Maximum number of results (default: 100)
        """
        start_time = time.time()

        # Validate path
        validated_path = path_validator.validate_read_path(directory)

        # Build args
        args = ["--directory", directory, "--user-id", DEFAULT_USER_ID]
        if name_pattern:
            args.extend(["--name", name_pattern])
        if content_pattern:
            args.extend(["--content", content_pattern])
        if case_sensitive:
            args.append("--case-sensitive")
        args.extend(["--max-results", str(max_results)])

        result = await executor.execute("fs", "search.py", args)

        # Audit log
        AuditLogger.log_tool_call(
            tool_name="fs_search",
            parameters={
                "directory": directory,
                "name_pattern": name_pattern,
                "content_pattern": content_pattern
            },
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False)
        )

        return json.dumps(result)
