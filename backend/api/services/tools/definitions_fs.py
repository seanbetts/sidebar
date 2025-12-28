"""File system tool definitions."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_fs_definitions() -> dict:
    """Return filesystem tool definitions."""
    return {
        "Browse Files": {
            "description": "List files and directories in R2-backed storage with glob pattern support",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory path (default: '.')"},
                    "pattern": {"type": "string", "description": "Glob pattern (default: '*')"},
                    "recursive": {"type": "boolean", "description": "Search recursively"},
                },
                "required": [],
            },
            "skill": "fs",
            "script": "list.py",
            "build_args": pm.build_fs_list_args,
            "validate_read": True,
        },
        "Read File": {
            "description": "Read file content from R2-backed storage",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path to read"},
                    "start_line": {"type": "integer", "description": "Start line number (optional)"},
                    "end_line": {"type": "integer", "description": "End line number (optional)"},
                },
                "required": ["path"],
            },
            "skill": "fs",
            "script": "read.py",
            "build_args": pm.build_fs_read_args,
            "validate_read": True,
        },
        "Write File": {
            "description": "Write content to file in R2-backed storage for project files and documents. For persistent, searchable notes use Create Note instead.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path to write"},
                    "content": {"type": "string", "description": "Content to write"},
                    "dry_run": {"type": "boolean", "description": "Preview without executing"},
                },
                "required": ["path", "content"],
            },
            "skill": "fs",
            "script": "write.py",
            "build_args": pm.build_fs_write_args,
            "validate_write": True,
        },
        "Search Files": {
            "description": "Search for files by name pattern or content in R2-backed storage",
            "input_schema": {
                "type": "object",
                "properties": {
                    "directory": {"type": "string", "description": "Directory to search (default: '.')"},
                    "name_pattern": {
                        "type": "string",
                        "description": "Filename pattern (* and ? wildcards)",
                    },
                    "content_pattern": {"type": "string", "description": "Content pattern (regex)"},
                    "case_sensitive": {"type": "boolean", "description": "Case-sensitive search"},
                },
            },
            "skill": "fs",
            "script": "search.py",
            "build_args": pm.build_fs_search_args,
            "validate_read": True,
        },
    }
