"""Miscellaneous tool definitions."""
from __future__ import annotations


def get_misc_definitions() -> dict:
    """Return miscellaneous tool definitions."""
    return {
        "Set UI Theme": {
            "description": "Set the UI theme to light or dark.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "theme": {"type": "string", "enum": ["light", "dark"]},
                },
                "required": ["theme"],
            },
            "skill": "ui-theme",
            "script": None,
            "build_args": None,
        },
        "Generate Prompts": {
            "description": "Generate the current system prompt output for preview.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "prompt-preview",
            "script": None,
            "build_args": None,
        },
        "Memory Tool": {
            "description": "Create, update, and manage persistent memory files. Paths should start with /memories.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "enum": ["view", "create", "str_replace", "insert", "delete", "rename"],
                    },
                    "path": {"type": "string"},
                    "view_range": {
                        "type": "array",
                        "items": {"type": "integer"},
                        "minItems": 2,
                        "maxItems": 2,
                    },
                    "file_text": {"type": "string"},
                    "content": {"type": "string"},
                    "old_str": {"type": "string"},
                    "new_str": {"type": "string"},
                    "insert_line": {"type": "integer"},
                    "insert_text": {"type": "string"},
                    "old_path": {"type": "string"},
                    "new_path": {"type": "string"},
                },
                "required": ["command"],
            },
            "skill": "memory",
            "script": None,
            "build_args": None,
        },
    }
