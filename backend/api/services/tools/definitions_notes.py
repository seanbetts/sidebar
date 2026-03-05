"""Notes tool definitions."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_notes_definitions() -> dict:
    """Return notes tool definitions."""
    return {
        "Create Note": {
            "description": (
                "Create a searchable, persistent note in the database. "
                "Notes are visible in the UI and fully searchable. "
                "Preferred for remembering information across sessions."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "content": {"type": "string", "description": "Note content text"},
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
                    "content": {"type": "string", "description": "Note content text"},
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
        "Archive Note": {
            "description": "Archive or unarchive a note by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "archived": {
                        "type": "boolean",
                        "description": "True to archive, false to unarchive",
                    },
                },
                "required": ["note_id", "archived"],
            },
            "skill": "notes",
            "script": "archive_note.py",
            "build_args": pm.build_notes_archive_args,
        },
        "Move Note": {
            "description": "Move a note to a folder by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                    "folder": {
                        "type": "string",
                        "description": "Destination folder path",
                    },
                },
                "required": ["note_id", "folder"],
            },
            "skill": "notes",
            "script": "move_note.py",
            "build_args": pm.build_notes_move_args,
        },
        "Create Note Folder": {
            "description": "Create a logical notes folder marker.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Folder path (for example: Projects/Alpha)",
                    },
                },
                "required": ["path"],
            },
            "skill": "notes",
            "script": "create_folder.py",
            "build_args": pm.build_notes_create_folder_args,
        },
        "Rename Note Folder": {
            "description": "Rename a notes folder path.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "old_path": {
                        "type": "string",
                        "description": "Current folder path",
                    },
                    "new_name": {
                        "type": "string",
                        "description": "New folder basename",
                    },
                },
                "required": ["old_path", "new_name"],
            },
            "skill": "notes",
            "script": "rename_folder.py",
            "build_args": pm.build_notes_rename_folder_args,
        },
        "Move Note Folder": {
            "description": "Move a notes folder to a new parent folder.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "old_path": {
                        "type": "string",
                        "description": "Current folder path",
                    },
                    "new_parent": {
                        "type": "string",
                        "description": "Destination parent folder (empty for root)",
                    },
                },
                "required": ["old_path"],
            },
            "skill": "notes",
            "script": "move_folder.py",
            "build_args": pm.build_notes_move_folder_args,
        },
        "Delete Note Folder": {
            "description": "Soft-delete all notes in a folder path.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Folder path to delete"},
                },
                "required": ["path"],
            },
            "skill": "notes",
            "script": "delete_folder.py",
            "build_args": pm.build_notes_delete_folder_args,
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
        "Download Note": {
            "description": (
                "Export a note as plain-text content plus filename metadata."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "note_id": {"type": "string", "description": "Note UUID"},
                },
                "required": ["note_id"],
            },
            "skill": "notes",
            "script": "download_note.py",
            "build_args": pm.build_notes_download_args,
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
