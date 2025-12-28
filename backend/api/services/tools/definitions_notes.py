"""Notes tool definitions."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_notes_definitions() -> dict:
    return {
        "Create Note": {
            "description": "Create a searchable, persistent markdown note in the database with metadata. Notes are visible in the UI and fully searchable. Preferred for remembering information across sessions.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Optional note title (defaults to first line of content)",
                    },
                    "content": {"type": "string", "description": "Markdown content"},
                    "folder": {"type": "string", "description": "Optional folder path"},
                    "tags": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["content"],
            },
            "skill": "notes",
            "script": "save_markdown.py",
            "build_args": pm.build_notes_create_args,
        },
        "Update Note": {
            "description": "Update an existing note in the database by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "title": {"type": "string", "description": "Optional note title"},
                    "content": {"type": "string", "description": "Markdown content"},
                },
                "required": ["note_id", "content"],
            },
            "skill": "notes",
            "script": "save_markdown.py",
            "build_args": pm.build_notes_update_args,
        },
        "Delete Note": {
            "description": "Delete a note in the database by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                },
                "required": ["note_id"],
            },
            "skill": "notes",
            "script": "delete_note.py",
            "build_args": pm.build_notes_delete_args,
        },
        "Pin Note": {
            "description": "Pin or unpin a note in the database.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "pinned": {"type": "boolean", "description": "Pin state"},
                },
                "required": ["note_id", "pinned"],
            },
            "skill": "notes",
            "script": "pin_note.py",
            "build_args": pm.build_notes_pin_args,
        },
        "Move Note": {
            "description": "Move a note to a folder by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "folder": {"type": "string", "description": "Destination folder path"},
                },
                "required": ["note_id", "folder"],
            },
            "skill": "notes",
            "script": "move_note.py",
            "build_args": pm.build_notes_move_args,
        },
        "Get Note": {
            "description": "Fetch a note by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                },
                "required": ["note_id"],
            },
            "skill": "notes",
            "script": "read_note.py",
            "build_args": pm.build_notes_read_args,
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
                    "title": {"type": "string"},
                },
            },
            "skill": "notes",
            "script": "list_notes.py",
            "build_args": pm.build_notes_list_args,
        },
        "Get Scratchpad": {
            "description": "Fetch the scratchpad note.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "notes",
            "script": "scratchpad_get.py",
            "build_args": pm.build_scratchpad_get_args,
        },
        "Update Scratchpad": {
            "description": "Update the scratchpad content.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "content": {"type": "string"},
                },
                "required": ["content"],
            },
            "skill": "notes",
            "script": "scratchpad_update.py",
            "build_args": pm.build_scratchpad_update_args,
        },
        "Clear Scratchpad": {
            "description": "Clear the scratchpad content.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "notes",
            "script": "scratchpad_clear.py",
            "build_args": pm.build_scratchpad_clear_args,
        },
    }
