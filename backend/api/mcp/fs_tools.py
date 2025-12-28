"""Filesystem MCP tool registration."""
from __future__ import annotations

import json
import time

from api.security.audit_logger import AuditLogger


def register_fs_tools(mcp, executor, path_validator, default_user_id: str) -> None:
    """Register filesystem tools with the MCP server.

    Args:
        mcp: FastMCP instance to register tools on.
        executor: Skill executor used to run scripts.
        path_validator: Validator for read/write paths.
        default_user_id: Default user ID for tool execution.
    """
    @mcp.tool()
    async def fs_list(
        path: str = ".",
        pattern: str = "*",
        recursive: bool = False,
    ) -> str:
        """List files in storage directory.

        Args:
            path: Directory path relative to storage (default: ".")
            pattern: Glob pattern to filter files (default: "*")
            recursive: List files recursively (default: false)
        """
        start_time = time.time()

        validated_path = path_validator.validate_read_path(path)

        args = [path, "--pattern", pattern, "--user-id", default_user_id]
        if recursive:
            args.append("--recursive")

        result = await executor.execute("fs", "list.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_list",
            parameters={"path": path, "pattern": pattern, "recursive": recursive},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_read(
        path: str,
        start_line: int = None,
        end_line: int = None,
    ) -> str:
        """Read file content from storage.

        Args:
            path: File path relative to storage
            start_line: Optional starting line number (1-indexed)
            end_line: Optional ending line number (inclusive)
        """
        start_time = time.time()

        validated_path = path_validator.validate_read_path(path)

        args = [path, "--user-id", default_user_id]
        if start_line and end_line:
            num_lines = end_line - start_line + 1
            args.extend(["--offset", str(start_line - 1), "--lines", str(num_lines)])
        elif end_line:
            args.extend(["--lines", str(end_line)])

        result = await executor.execute("fs", "read.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_read",
            parameters={"path": path, "start_line": start_line, "end_line": end_line},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_write(
        path: str,
        content: str,
        dry_run: bool = False,
    ) -> str:
        """Write content to file in storage.

        Args:
            path: File path relative to storage
            content: Content to write (replaces existing)
            dry_run: If true, validate but don't actually write
        """
        start_time = time.time()

        validated_path = path_validator.validate_write_path(path)

        if dry_run:
            AuditLogger.log_tool_call(
                tool_name="fs_write",
                parameters={"path": path, "dry_run": True},
                resolved_path=validated_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True,
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would write {len(content)} bytes to {path}",
            })

        args = [path, "--content", content, "--mode", "replace", "--user-id", default_user_id]
        result = await executor.execute("fs", "write.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_write",
            parameters={"path": path, "content_length": len(content)},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_delete(
        path: str,
        dry_run: bool = False,
    ) -> str:
        """Delete file or directory from storage.

        Args:
            path: File/directory path relative to storage
            dry_run: If true, validate but don't actually delete
        """
        start_time = time.time()

        validated_path = path_validator.validate_write_path(path)

        if dry_run:
            AuditLogger.log_tool_call(
                tool_name="fs_delete",
                parameters={"path": path, "dry_run": True},
                resolved_path=validated_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True,
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would delete {path}",
            })

        args = [path, "--user-id", default_user_id]
        result = await executor.execute("fs", "delete.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_delete",
            parameters={"path": path},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_move(
        source: str,
        destination: str,
        dry_run: bool = False,
    ) -> str:
        """Move file or directory to a new location in storage."""
        start_time = time.time()

        source_path = path_validator.validate_write_path(source)
        path_validator.validate_write_path(destination)

        if dry_run:
            AuditLogger.log_tool_call(
                tool_name="fs_move",
                parameters={"source": source, "destination": destination, "dry_run": True},
                resolved_path=source_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True,
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would move {source} to {destination}",
            })

        args = [source, destination, "--user-id", default_user_id]
        result = await executor.execute("fs", "move.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_move",
            parameters={"source": source, "destination": destination},
            resolved_path=source_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_rename(
        path: str,
        new_name: str,
        dry_run: bool = False,
    ) -> str:
        """Rename file or directory (stays in same directory)."""
        start_time = time.time()

        validated_path = path_validator.validate_write_path(path)

        if dry_run:
            AuditLogger.log_tool_call(
                tool_name="fs_rename",
                parameters={"path": path, "new_name": new_name, "dry_run": True},
                resolved_path=validated_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True,
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would rename to {new_name}",
            })

        args = [path, new_name, "--user-id", default_user_id]
        result = await executor.execute("fs", "rename.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_rename",
            parameters={"path": path, "new_name": new_name},
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_copy(
        source: str,
        destination: str,
        dry_run: bool = False,
    ) -> str:
        """Copy file or directory to a new location in storage."""
        start_time = time.time()

        source_path = path_validator.validate_read_path(source)
        path_validator.validate_write_path(destination)

        if dry_run:
            AuditLogger.log_tool_call(
                tool_name="fs_copy",
                parameters={"source": source, "destination": destination, "dry_run": True},
                resolved_path=source_path,
                duration_ms=(time.time() - start_time) * 1000,
                success=True,
            )
            return json.dumps({
                "success": True,
                "dry_run": True,
                "message": f"Would copy {source} to {destination}",
            })

        args = [source, destination, "--user-id", default_user_id]
        result = await executor.execute("fs", "copy.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_copy",
            parameters={"source": source, "destination": destination},
            resolved_path=source_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)

    @mcp.tool()
    async def fs_search(
        directory: str = ".",
        name_pattern: str = None,
        content_pattern: str = None,
        case_sensitive: bool = False,
        max_results: int = 100,
    ) -> str:
        """Search for files by name or content in storage."""
        start_time = time.time()

        validated_path = path_validator.validate_read_path(directory)

        args = ["--directory", directory, "--user-id", default_user_id]
        if name_pattern:
            args.extend(["--name", name_pattern])
        if content_pattern:
            args.extend(["--content", content_pattern])
        if case_sensitive:
            args.append("--case-sensitive")
        args.extend(["--max-results", str(max_results)])

        result = await executor.execute("fs", "search.py", args)

        AuditLogger.log_tool_call(
            tool_name="fs_search",
            parameters={
                "directory": directory,
                "name_pattern": name_pattern,
                "content_pattern": content_pattern,
            },
            resolved_path=validated_path,
            duration_ms=(time.time() - start_time) * 1000,
            success=result.get("success", False),
        )

        return json.dumps(result)
