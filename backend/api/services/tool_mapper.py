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

    @staticmethod
    def _normalize_result(result: Any) -> Dict[str, Any]:
        if isinstance(result, dict):
            success = bool(result.get("success", False))
            data = result.get("data")
            error = result.get("error")

            if success and data is None:
                data = {
                    key: value
                    for key, value in result.items()
                    if key not in {"success", "error"}
                }

            if not success and not error:
                error = "Unknown error"

            return {
                "success": success,
                "data": data,
                "error": error
            }

        return {
            "success": True,
            "data": result,
            "error": None
        }

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
            },
            {
                "name": "notes_delete",
                "description": "Delete a note in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"}
                    },
                    "required": ["note_id"]
                }
            },
            {
                "name": "notes_pin",
                "description": "Pin or unpin a note in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "pinned": {"type": "boolean", "description": "Pin state"}
                    },
                    "required": ["note_id", "pinned"]
                }
            },
            {
                "name": "notes_move",
                "description": "Move a note to a folder by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "folder": {"type": "string", "description": "Destination folder path"}
                    },
                    "required": ["note_id", "folder"]
                }
            },
            {
                "name": "notes_get",
                "description": "Fetch a note by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"}
                    },
                    "required": ["note_id"]
                }
            },
            {
                "name": "notes_list",
                "description": "List notes with optional filters.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "folder": {"type": "string"},
                        "pinned": {"type": "boolean"},
                        "archived": {"type": "boolean"},
                        "created_after": {"type": "string"},
                        "created_before": {"type": "string"},
                        "updated_after": {"type": "string"},
                        "updated_before": {"type": "string"},
                        "opened_after": {"type": "string"},
                        "opened_before": {"type": "string"},
                        "title": {"type": "string"}
                    }
                }
            },
            {
                "name": "scratchpad_get",
                "description": "Fetch the scratchpad note.",
                "input_schema": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "scratchpad_update",
                "description": "Update the scratchpad content.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "content": {"type": "string"}
                    },
                    "required": ["content"]
                }
            },
            {
                "name": "scratchpad_clear",
                "description": "Clear the scratchpad content.",
                "input_schema": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "website_delete",
                "description": "Delete a website in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string", "description": "Website UUID"}
                    },
                    "required": ["website_id"]
                }
            },
            {
                "name": "website_pin",
                "description": "Pin or unpin a website in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"},
                        "pinned": {"type": "boolean"}
                    },
                    "required": ["website_id", "pinned"]
                }
            },
            {
                "name": "website_archive",
                "description": "Archive or unarchive a website in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"},
                        "archived": {"type": "boolean"}
                    },
                    "required": ["website_id", "archived"]
                }
            },
            {
                "name": "website_read",
                "description": "Fetch a website by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"}
                    },
                    "required": ["website_id"]
                }
            },
            {
                "name": "website_list",
                "description": "List websites with optional filters.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "domain": {"type": "string"},
                        "pinned": {"type": "boolean"},
                        "archived": {"type": "boolean"},
                        "created_after": {"type": "string"},
                        "created_before": {"type": "string"},
                        "updated_after": {"type": "string"},
                        "updated_before": {"type": "string"},
                        "opened_after": {"type": "string"},
                        "opened_before": {"type": "string"},
                        "published_after": {"type": "string"},
                        "published_before": {"type": "string"},
                        "title": {"type": "string"}
                    }
                }
            },
            {
                "name": "ui_theme_set",
                "description": "Set the UI theme to light or dark.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "theme": {"type": "string", "enum": ["light", "dark"]}
                    },
                    "required": ["theme"]
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

                return self._normalize_result(result)

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

                return self._normalize_result(result)

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

                return self._normalize_result(result)

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

                return self._normalize_result(result)

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

                return self._normalize_result(result)

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

                return self._normalize_result(result)

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

                return self._normalize_result(result)

            elif name == "notes_delete":
                note_id = parameters.get("note_id")
                args = [note_id, "--database"]

                result = await self.executor.execute("notes", "delete_note.py", args)

                AuditLogger.log_tool_call(
                    tool_name="notes_delete",
                    parameters={"note_id": note_id},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "notes_pin":
                note_id = parameters.get("note_id")
                pinned = parameters.get("pinned", False)
                args = [note_id, "--pinned", str(pinned).lower(), "--database"]

                result = await self.executor.execute("notes", "pin_note.py", args)

                AuditLogger.log_tool_call(
                    tool_name="notes_pin",
                    parameters={"note_id": note_id, "pinned": pinned},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "notes_move":
                note_id = parameters.get("note_id")
                folder = parameters.get("folder", "")
                args = [note_id, "--folder", folder, "--database"]

                result = await self.executor.execute("notes", "move_note.py", args)

                AuditLogger.log_tool_call(
                    tool_name="notes_move",
                    parameters={"note_id": note_id, "folder": folder},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "notes_get":
                note_id = parameters.get("note_id")
                args = [note_id, "--database"]

                result = await self.executor.execute("notes", "read_note.py", args)

                AuditLogger.log_tool_call(
                    tool_name="notes_get",
                    parameters={"note_id": note_id},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "notes_list":
                args = ["--database"]
                for key, flag in [
                    ("folder", "--folder"),
                    ("pinned", "--pinned"),
                    ("archived", "--archived"),
                    ("created_after", "--created-after"),
                    ("created_before", "--created-before"),
                    ("updated_after", "--updated-after"),
                    ("updated_before", "--updated-before"),
                    ("opened_after", "--opened-after"),
                    ("opened_before", "--opened-before"),
                    ("title", "--title"),
                ]:
                    value = parameters.get(key)
                    if value is not None:
                        args.extend([flag, str(value)])

                result = await self.executor.execute("notes", "list_notes.py", args)

                AuditLogger.log_tool_call(
                    tool_name="notes_list",
                    parameters=parameters,
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "scratchpad_get":
                args = ["--database"]

                result = await self.executor.execute("notes", "scratchpad_get.py", args)

                AuditLogger.log_tool_call(
                    tool_name="scratchpad_get",
                    parameters={},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "scratchpad_update":
                content = parameters.get("content", "")
                args = ["--content", content, "--database"]

                result = await self.executor.execute("notes", "scratchpad_update.py", args)

                AuditLogger.log_tool_call(
                    tool_name="scratchpad_update",
                    parameters={"content": "<redacted>"},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "scratchpad_clear":
                args = ["--database"]

                result = await self.executor.execute("notes", "scratchpad_clear.py", args)

                AuditLogger.log_tool_call(
                    tool_name="scratchpad_clear",
                    parameters={},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "website_delete":
                website_id = parameters.get("website_id")
                args = [website_id, "--database"]

                result = await self.executor.execute("web-save", "delete_website.py", args)

                AuditLogger.log_tool_call(
                    tool_name="website_delete",
                    parameters={"website_id": website_id},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "website_pin":
                website_id = parameters.get("website_id")
                pinned = parameters.get("pinned", False)
                args = [website_id, "--pinned", str(pinned).lower(), "--database"]

                result = await self.executor.execute("web-save", "pin_website.py", args)

                AuditLogger.log_tool_call(
                    tool_name="website_pin",
                    parameters={"website_id": website_id, "pinned": pinned},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "website_archive":
                website_id = parameters.get("website_id")
                archived = parameters.get("archived", False)
                args = [website_id, "--archived", str(archived).lower(), "--database"]

                result = await self.executor.execute("web-save", "archive_website.py", args)

                AuditLogger.log_tool_call(
                    tool_name="website_archive",
                    parameters={"website_id": website_id, "archived": archived},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "website_read":
                website_id = parameters.get("website_id")
                args = [website_id, "--database"]

                result = await self.executor.execute("web-save", "read_website.py", args)

                AuditLogger.log_tool_call(
                    tool_name="website_read",
                    parameters={"website_id": website_id},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "website_list":
                args = ["--database"]
                for key, flag in [
                    ("domain", "--domain"),
                    ("pinned", "--pinned"),
                    ("archived", "--archived"),
                    ("created_after", "--created-after"),
                    ("created_before", "--created-before"),
                    ("updated_after", "--updated-after"),
                    ("updated_before", "--updated-before"),
                    ("opened_after", "--opened-after"),
                    ("opened_before", "--opened-before"),
                    ("published_after", "--published-after"),
                    ("published_before", "--published-before"),
                    ("title", "--title"),
                ]:
                    value = parameters.get(key)
                    if value is not None:
                        args.extend([flag, str(value)])

                result = await self.executor.execute("web-save", "list_websites.py", args)

                AuditLogger.log_tool_call(
                    tool_name="website_list",
                    parameters=parameters,
                    duration_ms=(time.time() - start_time) * 1000,
                    success=result.get("success", False)
                )

                return self._normalize_result(result)

            elif name == "ui_theme_set":
                theme = parameters.get("theme")
                if theme not in {"light", "dark"}:
                    return self._normalize_result({"success": False, "error": "Invalid theme"})

                result = {"success": True, "data": {"theme": theme}}

                AuditLogger.log_tool_call(
                    tool_name="ui_theme_set",
                    parameters={"theme": theme},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=True
                )

                return self._normalize_result(result)

            else:
                return self._normalize_result({"success": False, "error": f"Unknown tool: {name}"})

        except Exception as e:
            AuditLogger.log_tool_call(
                tool_name=name,
                parameters=parameters,
                duration_ms=(time.time() - start_time) * 1000,
                success=False,
                error=str(e)
            )
            return self._normalize_result({"success": False, "error": str(e)})
