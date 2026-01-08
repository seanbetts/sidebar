"""File system tool definitions."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_fs_definitions() -> dict:
    """Return filesystem tool definitions."""
    return {
        "Browse Files": {
            "description": "List ingested files and folders in R2-backed storage (paths map to ingested records).",
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
            "skill": "fs",
            "script": "list.py",
            "build_args": pm.build_fs_list_args,
            "validate_read": True,
        },
        "Read File": {
            "description": "Read extracted text/ai.md content for ingested files (including PDFs). Returns frontmatter + text, not raw binary.",
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
            "skill": "fs",
            "script": "read.py",
            "build_args": pm.build_fs_read_args,
            "validate_read": True,
        },
        "Write File": {
            "description": "Create/update ingested text files (stored in R2 + DB). Use for files; use Create Note for notes.",
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
            "skill": "fs",
            "script": "write.py",
            "build_args": pm.build_fs_write_args,
            "validate_write": True,
        },
        "Search Files": {
            "description": "Search ingested files by name or extracted text content (including PDF text).",
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
            "skill": "fs",
            "script": "search.py",
            "build_args": pm.build_fs_search_args,
            "validate_read": True,
        },
    }
