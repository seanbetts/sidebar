---
name: notes
description: Notes operations backed by the database - create, update, read, list, rename, move, pin, archive, delete notes and folders, plus scratchpad management.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Notes Operations

Database-backed operations for notes and scratchpad content.

## Scripts

- `save_markdown.py` - Create, update, or append note content
- `read_note.py` - Fetch a note by ID
- `list_notes.py` - List notes with filters
- `rename_note.py` - Rename a note title
- `pin_note.py` - Pin or unpin a note
- `archive_note.py` - Archive or unarchive a note
- `move_note.py` - Move a note to a folder
- `delete_note.py` - Soft-delete a note
- `download_note.py` - Export note markdown content + filename
- `create_folder.py` - Create a logical folder marker
- `rename_folder.py` - Rename a folder path
- `move_folder.py` - Move a folder path
- `delete_folder.py` - Soft-delete notes in a folder
- `scratchpad_get.py` - Fetch scratchpad
- `scratchpad_update.py` - Update scratchpad content
- `scratchpad_clear.py` - Clear scratchpad content

All scripts support `--json` output.
