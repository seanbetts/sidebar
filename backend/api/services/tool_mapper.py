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

        # Single source of truth for all tools
        self.tools = {
            "Browse Files": {
                "description": "List files and directories in workspace with glob pattern support",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Directory path (default: '.')"},
                        "pattern": {"type": "string", "description": "Glob pattern (default: '*')"},
                        "recursive": {"type": "boolean", "description": "Search recursively"}
                    },
                    "required": []
                },
                "skill": "fs",
                "script": "list.py",
                "build_args": lambda p: self._build_fs_list_args(p),
                "validate_read": True
            },
            "Read File": {
                "description": "Read file content from workspace",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "File path to read"},
                        "start_line": {"type": "integer", "description": "Start line number (optional)"},
                        "end_line": {"type": "integer", "description": "End line number (optional)"}
                    },
                    "required": ["path"]
                },
                "skill": "fs",
                "script": "read.py",
                "build_args": lambda p: self._build_fs_read_args(p),
                "validate_read": True
            },
            "Write File": {
                "description": "Write content to file in workspace (writable paths: notes/, documents/)",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "File path to write"},
                        "content": {"type": "string", "description": "Content to write"},
                        "dry_run": {"type": "boolean", "description": "Preview without executing"}
                    },
                    "required": ["path", "content"]
                },
                "skill": "fs",
                "script": "write.py",
                "build_args": lambda p: self._build_fs_write_args(p),
                "validate_write": True
            },
            "Search Files": {
                "description": "Search for files by name pattern or content in workspace",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "directory": {"type": "string", "description": "Directory to search (default: '.')"},
                        "name_pattern": {"type": "string", "description": "Filename pattern (* and ? wildcards)"},
                        "content_pattern": {"type": "string", "description": "Content pattern (regex)"},
                        "case_sensitive": {"type": "boolean", "description": "Case-sensitive search"}
                    }
                },
                "skill": "fs",
                "script": "search.py",
                "build_args": lambda p: self._build_fs_search_args(p),
                "validate_read": True
            },
            "Create Note": {
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
                },
                "skill": "notes",
                "script": "save_markdown.py",
                "build_args": lambda p: self._build_notes_create_args(p)
            },
            "Update Note": {
                "description": "Update an existing note in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "title": {"type": "string", "description": "Optional note title"},
                        "content": {"type": "string", "description": "Markdown content"}
                    },
                    "required": ["note_id", "content"]
                },
                "skill": "notes",
                "script": "save_markdown.py",
                "build_args": lambda p: self._build_notes_update_args(p)
            },
            "Delete Note": {
                "description": "Delete a note in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"}
                    },
                    "required": ["note_id"]
                },
                "skill": "notes",
                "script": "delete_note.py",
                "build_args": lambda p: [p["note_id"], "--database"]
            },
            "Pin Note": {
                "description": "Pin or unpin a note in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "pinned": {"type": "boolean", "description": "Pin state"}
                    },
                    "required": ["note_id", "pinned"]
                },
                "skill": "notes",
                "script": "pin_note.py",
                "build_args": lambda p: [p["note_id"], "--pinned", str(p["pinned"]).lower(), "--database"]
            },
            "Move Note": {
                "description": "Move a note to a folder by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"},
                        "folder": {"type": "string", "description": "Destination folder path"}
                    },
                    "required": ["note_id", "folder"]
                },
                "skill": "notes",
                "script": "move_note.py",
                "build_args": lambda p: [p["note_id"], "--folder", p["folder"], "--database"]
            },
            "Get Note": {
                "description": "Fetch a note by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "note_id": {"type": "string", "description": "Note UUID"}
                    },
                    "required": ["note_id"]
                },
                "skill": "notes",
                "script": "read_note.py",
                "build_args": lambda p: [p["note_id"], "--database"]
            },
            "List Notes": {
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
                },
                "skill": "notes",
                "script": "list_notes.py",
                "build_args": lambda p: self._build_notes_list_args(p)
            },
            "Get Scratchpad": {
                "description": "Fetch the scratchpad note.",
                "input_schema": {
                    "type": "object",
                    "properties": {}
                },
                "skill": "notes",
                "script": "scratchpad_get.py",
                "build_args": lambda p: ["--database"]
            },
            "Update Scratchpad": {
                "description": "Update the scratchpad content.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "content": {"type": "string"}
                    },
                    "required": ["content"]
                },
                "skill": "notes",
                "script": "scratchpad_update.py",
                "build_args": lambda p: ["--content", p["content"], "--database"]
            },
            "Clear Scratchpad": {
                "description": "Clear the scratchpad content.",
                "input_schema": {
                    "type": "object",
                    "properties": {}
                },
                "skill": "notes",
                "script": "scratchpad_clear.py",
                "build_args": lambda p: ["--database"]
            },
            "Save Website": {
                "description": "Save a website to the database (visible in UI).",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "url": {"type": "string", "description": "Website URL"}
                    },
                    "required": ["url"]
                },
                "skill": "web-save",
                "script": "save_url.py",
                "build_args": lambda p: [p["url"], "--database"]
            },
            "Delete Website": {
                "description": "Delete a website in the database by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string", "description": "Website UUID"}
                    },
                    "required": ["website_id"]
                },
                "skill": "web-save",
                "script": "delete_website.py",
                "build_args": lambda p: [p["website_id"], "--database"]
            },
            "Pin Website": {
                "description": "Pin or unpin a website in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"},
                        "pinned": {"type": "boolean"}
                    },
                    "required": ["website_id", "pinned"]
                },
                "skill": "web-save",
                "script": "pin_website.py",
                "build_args": lambda p: [p["website_id"], "--pinned", str(p["pinned"]).lower(), "--database"]
            },
            "Archive Website": {
                "description": "Archive or unarchive a website in the database.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"},
                        "archived": {"type": "boolean"}
                    },
                    "required": ["website_id", "archived"]
                },
                "skill": "web-save",
                "script": "archive_website.py",
                "build_args": lambda p: [p["website_id"], "--archived", str(p["archived"]).lower(), "--database"]
            },
            "Read Website": {
                "description": "Fetch a website by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "website_id": {"type": "string"}
                    },
                    "required": ["website_id"]
                },
                "skill": "web-save",
                "script": "read_website.py",
                "build_args": lambda p: [p["website_id"], "--database"]
            },
            "List Websites": {
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
                },
                "skill": "web-save",
                "script": "list_websites.py",
                "build_args": lambda p: self._build_website_list_args(p)
            },
            "Set UI Theme": {
                "description": "Set the UI theme to light or dark.",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "theme": {"type": "string", "enum": ["light", "dark"]}
                    },
                    "required": ["theme"]
                },
                "skill": None,  # Special case - no skill execution
                "script": None,
                "build_args": None
            }
        }

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
        """Convert tool configs to Claude tool schema."""
        return [
            {
                "name": name,
                "description": config["description"],
                "input_schema": config["input_schema"]
            }
            for name, config in self.tools.items()
        ]

    async def execute_tool(self, name: str, parameters: dict) -> Dict[str, Any]:
        """Execute tool via skill executor."""
        start_time = time.time()

        try:
            # Get tool config
            tool_config = self.tools.get(name)
            if not tool_config:
                return self._normalize_result({
                    "success": False,
                    "error": f"Unknown tool: {name}"
                })

            # Special case: UI theme (no skill execution)
            if name == "Set UI Theme":
                theme = parameters.get("theme")
                if theme not in {"light", "dark"}:
                    return self._normalize_result({"success": False, "error": "Invalid theme"})

                result = {"success": True, "data": {"theme": theme}}

                AuditLogger.log_tool_call(
                    tool_name=name,
                    parameters={"theme": theme},
                    duration_ms=(time.time() - start_time) * 1000,
                    success=True
                )

                return self._normalize_result(result)

            # Validate paths if needed
            if tool_config.get("validate_write"):
                if "path" in parameters:
                    self.path_validator.validate_write_path(parameters["path"])
            elif tool_config.get("validate_read"):
                path_to_validate = parameters.get("path") or parameters.get("directory", ".")
                self.path_validator.validate_read_path(path_to_validate)

            # Build arguments using the tool's build function
            args = tool_config["build_args"](parameters)

            # Execute skill
            result = await self.executor.execute(
                tool_config["skill"],
                tool_config["script"],
                args
            )

            # Log execution (redact sensitive content)
            log_params = parameters.copy()
            if "content" in log_params and name == "Update Scratchpad":
                log_params["content"] = "<redacted>"
            if "content" in log_params and name in ["Create Note", "Update Note", "Write File"]:
                log_params.pop("content", None)

            AuditLogger.log_tool_call(
                tool_name=name,
                parameters=log_params,
                duration_ms=(time.time() - start_time) * 1000,
                success=result.get("success", False)
            )

            return self._normalize_result(result)

        except Exception as e:
            AuditLogger.log_tool_call(
                tool_name=name,
                parameters=parameters,
                duration_ms=(time.time() - start_time) * 1000,
                success=False,
                error=str(e)
            )
            return self._normalize_result({"success": False, "error": str(e)})

    # Argument builders for each tool type
    def _build_fs_list_args(self, params: dict) -> list:
        path = params.get("path", ".")
        pattern = params.get("pattern", "*")
        recursive = params.get("recursive", False)

        args = [path, "--pattern", pattern]
        if recursive:
            args.append("--recursive")
        return args

    def _build_fs_read_args(self, params: dict) -> list:
        args = [params["path"]]
        if "start_line" in params:
            args.extend(["--start-line", str(params["start_line"])])
        if "end_line" in params:
            args.extend(["--end-line", str(params["end_line"])])
        return args

    def _build_fs_write_args(self, params: dict) -> list:
        args = [params["path"], "--content", params["content"]]
        if params.get("dry_run"):
            args.append("--dry-run")
        return args

    def _build_fs_search_args(self, params: dict) -> list:
        directory = params.get("directory", ".")
        name_pattern = params.get("name_pattern")
        content_pattern = params.get("content_pattern")
        case_sensitive = params.get("case_sensitive", False)

        args = ["--directory", directory]
        if name_pattern:
            args.extend(["--name", name_pattern])
        if content_pattern:
            args.extend(["--content", content_pattern])
        if case_sensitive:
            args.append("--case-sensitive")
        return args

    def _build_notes_create_args(self, params: dict) -> list:
        args = [
            params.get("title", ""),
            "--content",
            params["content"],
            "--mode",
            "create",
            "--database"
        ]
        if "folder" in params:
            args.extend(["--folder", params["folder"]])
        if "tags" in params:
            args.extend(["--tags", ",".join(params["tags"])])
        return args

    def _build_notes_update_args(self, params: dict) -> list:
        return [
            params.get("title", ""),
            "--content",
            params["content"],
            "--mode",
            "update",
            "--note-id",
            params["note_id"],
            "--database"
        ]

    def _build_notes_list_args(self, params: dict) -> list:
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
            value = params.get(key)
            if value is not None:
                args.extend([flag, str(value)])
        return args

    def _build_website_list_args(self, params: dict) -> list:
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
            value = params.get(key)
            if value is not None:
                args.extend([flag, str(value)])
        return args
