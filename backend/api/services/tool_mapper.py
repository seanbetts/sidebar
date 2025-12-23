"""Maps MCP tools to Claude tool definitions and handles execution."""
import json
import time
from typing import Dict, Any, List
from api.config import settings
from api.executors.skill_executor import SkillExecutor
from api.security.path_validator import PathValidator
from api.security.audit_logger import AuditLogger


class ToolMapper:
    """Maps MCP tools to Claude tool definitions."""

    def __init__(self):
        self.executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
        self.path_validator = PathValidator(settings.workspace_base, settings.writable_paths)

    def get_claude_tools(self) -> List[Dict[str, Any]]:
        """Convert MCP tools to Claude tool schema."""
        return [
            {
                "name": "fs_list",
                "description": "List files and directories in workspace with glob pattern support",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Directory path (default: '.')"},
                        "pattern": {"type": "string", "description": "Glob pattern (default: '*')"},
                        "recursive": {"type": "boolean", "description": "Search recursively"}
                    },
                    "required": []
                }
            },
            {
                "name": "fs_read",
                "description": "Read file content from workspace",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "File path to read"},
                        "start_line": {"type": "integer", "description": "Start line number (optional)"},
                        "end_line": {"type": "integer", "description": "End line number (optional)"}
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "fs_write",
                "description": "Write content to file in workspace (writable paths: notes/, documents/)",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "File path to write"},
                        "content": {"type": "string", "description": "Content to write"},
                        "dry_run": {"type": "boolean", "description": "Preview without executing"}
                    },
                    "required": ["path", "content"]
                }
            },
            {
                "name": "fs_search",
                "description": "Search for files by name pattern or content in workspace",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "directory": {"type": "string", "description": "Directory to search (default: '.')"},
                        "name_pattern": {"type": "string", "description": "Filename pattern (* and ? wildcards)"},
                        "content_pattern": {"type": "string", "description": "Content pattern (regex)"},
                        "case_sensitive": {"type": "boolean", "description": "Case-sensitive search"}
                    }
                }
            },
            {
                "name": "notes_create",
                "description": "Create a markdown note in the database (visible in UI).",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "Optional note title"},
                        "content": {"type": "string", "description": "Markdown content"},
                        "folder": {"type": "string", "description": "Optional folder path"},
                        "tags": {"type": "array", "items": {"type": "string"}}
                    },
                    "required": ["content"]
                }
            },
            {
                "name": "notes_update",
                "description": "Update an existing note in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "title": {"type": "string", "description": "Optional note title"},
                        "content": {"type": "string", "description": "Markdown content"}
                    },
                    "required": ["note_id", "content"]
                }
            },
            {
                "name": "website_save",
                "description": "Save a website to the database (visible in UI).",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "url": {"type": "string", "description": "Website URL"}
                    },
                    "required": ["url"]
                }
            }
        ]

    async def execute_tool(self, name: str, parameters: dict) -> Dict[str, Any]:
        """Execute tool via skill executor."""
        start_time = time.time()

        try:
            # Map tool name to skill execution
            if name == "fs_list":
                path = parameters.get("path", ".")
                pattern = parameters.get("pattern", "*")
                recursive = parameters.get("recursive", False)

                validated_path = self.path_validator.validate_read_path(path)

                args = [path, "--pattern", pattern]
                if recursive:
                    args.append("--recursive")

                result = await self.executor.execute("fs", "list.py", args)

                AuditLogger.log_tool_call(
                    tool_name="fs_list",
                    parameters=parameters,
                    resolved_path=validated_path,
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return result

            elif name == "fs_read":
                path = parameters.get("path")
                start_line = parameters.get("start_line")
                end_line = parameters.get("end_line")

                validated_path = self.path_validator.validate_read_path(path)

                args = [path]
                if start_line is not None:
                    args.extend(["--start-line", str(start_line)])
                if end_line is not None:
                    args.extend(["--end-line", str(end_line)])

                result = await self.executor.execute("fs", "read.py", args)

                AuditLogger.log_tool_call(
                    tool_name="fs_read",
                    parameters=parameters,
                    resolved_path=validated_path,
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return result

            elif name == "fs_write":
                path = parameters.get("path")
                content = parameters.get("content")
                dry_run = parameters.get("dry_run", False)

                validated_path = self.path_validator.validate_write_path(path)

                args = [path, "--content", content]
                if dry_run:
                    args.append("--dry-run")

                result = await self.executor.execute("fs", "write.py", args)

                AuditLogger.log_tool_call(
                    tool_name="fs_write",
                    parameters={"path": path, "dry_run": dry_run},  # Don't log content
                    resolved_path=validated_path,
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return result

            elif name == "fs_search":
                directory = parameters.get("directory", ".")
                name_pattern = parameters.get("name_pattern")
                content_pattern = parameters.get("content_pattern")
                case_sensitive = parameters.get("case_sensitive", False)

                validated_path = self.path_validator.validate_read_path(directory)

                args = ["--directory", directory]
                if name_pattern:
                    args.extend(["--name", name_pattern])
                if content_pattern:
                    args.extend(["--content", content_pattern])
                if case_sensitive:
                    args.append("--case-sensitive")

                result = await self.executor.execute("fs", "search.py", args)

                AuditLogger.log_tool_call(
                    tool_name="fs_search",
                    parameters=parameters,
                    resolved_path=validated_path,
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return result

            elif name == "notes_create":
                title = parameters.get("title", "")
                content = parameters.get("content", "")
                folder = parameters.get("folder")
                tags = parameters.get("tags")

                args = [title, "--content", content, "--mode", "create", "--database"]
                if folder:
                    args.extend(["--folder", folder])
                if tags:
                    args.extend(["--tags", ",".join(tags)])

                result = await self.executor.execute("notes", "save_markdown.py", args)

                AuditLogger.log_tool_call(
                    tool_name="notes_create",
                    parameters={"title": title, "folder": folder, "tags": tags},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return result

            elif name == "notes_update":
                note_id = parameters.get("note_id")
                title = parameters.get("title", "")
                content = parameters.get("content", "")

                args = [
                    title,
                    "--content",
                    content,
                    "--mode",
                    "update",
                    "--note-id",
                    note_id,
                    "--database",
                ]

                result = await self.executor.execute("notes", "save_markdown.py", args)

                AuditLogger.log_tool_call(
                    tool_name="notes_update",
                    parameters={"note_id": note_id, "title": title},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return result

            elif name == "website_save":
                url = parameters.get("url", "")
                args = [url, "--database"]

                result = await self.executor.execute("web-save", "save_url.py", args)

                AuditLogger.log_tool_call(
                    tool_name="website_save",
                    parameters={"url": url},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return result

            else:
                return {"success": False, "error": f"Unknown tool: {name}"}

        except Exception as e:
            AuditLogger.log_tool_call(
                tool_name=name,
                parameters=parameters,
                duration_ms=(time.time() - start_time) * 1000,
                success=False,
                error=str(e)
            )
            return {"success": False, "error": str(e)}
