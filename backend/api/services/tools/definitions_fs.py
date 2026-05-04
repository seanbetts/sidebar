"""File system tool definitions."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_fs_definitions() -> dict:
    """Return filesystem tool definitions."""
    return {
        "Browse Files": {
            "description": (
                "List ingested files and folders in R2-backed storage "
                "(paths map to ingested records)."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Directory path (default: '.')",
                    },
                    "pattern": {
                        "type": "string",
                        "description": "Glob pattern (default: '*')",
                    },
                    "recursive": {
                        "type": "boolean",
                        "description": "Search recursively",
                    },
                },
                "required": [],
            },
            "skill": "files",
            "script": "list.py",
            "build_args": pm.build_fs_list_args,
            "validate_read": True,
        },
        "Read File": {
            "description": (
                "Read extracted text/ai.md content for ingested files "
                "(including PDFs). Returns frontmatter + text, not raw binary."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path to read"},
                    "start_line": {
                        "type": "integer",
                        "description": "Start line number (optional)",
                    },
                    "end_line": {
                        "type": "integer",
                        "description": "End line number (optional)",
                    },
                },
                "required": ["path"],
            },
            "skill": "files",
            "script": "read.py",
            "build_args": pm.build_fs_read_args,
            "validate_read": True,
        },
        "Open File": {
            "description": (
                "Request that the app opens an ingested file in the workspace "
                "without reading extracted content into chat. Use file_id when "
                "available, otherwise pass the storage path returned by file tools."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "file_id": {"type": "string", "description": "Ingested file ID"},
                    "path": {
                        "type": "string",
                        "description": "File path when an ingested file ID is unavailable",
                    },
                    "title": {
                        "type": "string",
                        "description": "Optional file title for the UI handoff",
                    },
                },
                "required": [],
            },
            "skill": "files",
            "script": None,
            "build_args": None,
        },
        "Write File": {
            "description": (
                "Create/update ingested text files (stored in R2 + DB). "
                "Use for files; use Create Note for notes."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path to write"},
                    "content": {"type": "string", "description": "Content to write"},
                    "dry_run": {
                        "type": "boolean",
                        "description": "Preview without executing",
                    },
                },
                "required": ["path", "content"],
            },
            "skill": "files",
            "script": "write.py",
            "build_args": pm.build_fs_write_args,
            "validate_write": True,
        },
        "Delete File": {
            "description": (
                "Delete an ingested file or folder path "
                "(soft delete in DB + derivative cleanup)."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File or directory path to delete",
                    },
                    "recursive": {
                        "type": "boolean",
                        "description": "Required for directory-style path deletes",
                    },
                },
                "required": ["path"],
            },
            "skill": "files",
            "script": "delete.py",
            "build_args": pm.build_fs_delete_args,
            "validate_write": True,
        },
        "Rename File": {
            "description": (
                "Rename an ingested file or directory in-place " "(same parent path)."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Existing file or directory path",
                    },
                    "new_name": {
                        "type": "string",
                        "description": "New name (not a path)",
                    },
                    "dry_run": {
                        "type": "boolean",
                        "description": "Preview rename without executing",
                    },
                },
                "required": ["path", "new_name"],
            },
            "skill": "files",
            "script": "rename.py",
            "build_args": pm.build_fs_rename_args,
            "validate_write": True,
        },
        "Pin File": {
            "description": "Set pinned state for an ingested file by path.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File path to pin/unpin",
                    },
                    "pinned": {
                        "type": "boolean",
                        "description": "True to pin, false to unpin",
                    },
                },
                "required": ["path", "pinned"],
            },
            "skill": "files",
            "script": "pin.py",
            "build_args": pm.build_fs_pin_args,
            "validate_write": True,
        },
        "Search Files": {
            "description": (
                "Search ingested files by name or extracted text content "
                "(including PDF text)."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "directory": {
                        "type": "string",
                        "description": "Directory to search (default: '.')",
                    },
                    "name_pattern": {
                        "type": "string",
                        "description": "Filename pattern (* and ? wildcards)",
                    },
                    "content_pattern": {
                        "type": "string",
                        "description": "Content pattern (regex)",
                    },
                    "case_sensitive": {
                        "type": "boolean",
                        "description": "Case-sensitive search",
                    },
                },
            },
            "skill": "files",
            "script": "search.py",
            "build_args": pm.build_fs_search_args,
            "validate_read": True,
        },
    }
