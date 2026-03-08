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

Database-backed operations for semantic note documents and scratchpad content.
Legacy markdown note writers and legacy RTF migration helpers are retired.

## Scripts

- `save_note_document.py` - Create, update, or append semantic note documents
- `read_note.py` - Fetch a note by ID
- `list_notes.py` - List notes with filters
- `rename_note.py` - Rename a note title
- `pin_note.py` - Pin or unpin a note
- `archive_note.py` - Archive or unarchive a note
- `move_note.py` - Move a note to a folder
- `delete_note.py` - Soft-delete a note
- `download_note.py` - Export derived plain-text note content + filename
- `create_folder.py` - Create a logical folder marker
- `rename_folder.py` - Rename a folder path
- `move_folder.py` - Move a folder path
- `delete_folder.py` - Soft-delete notes in a folder
- `scratchpad_get.py` - Fetch scratchpad
- `scratchpad_update.py` - Update scratchpad semantic document content
- `scratchpad_clear.py` - Clear scratchpad content

All scripts support `--json` output.

## Semantic Document Contract

Notes writes use canonical semantic note documents:

- `document.version` is currently `1`
- `document.blocks` currently supports paragraph blocks for AI writes
- paragraph `content` is a list of inline segments with `text` and `marks`
- supported inline marks are `bold`, `italic`, and `underline`

Titles are derived from the first non-empty projected plain-text line. Literal `#`
prefixes remain part of the title when they are part of the content.

## Append Behavior

Append is document-native:

- pass a semantic `document` body to `save_note_document.py --mode append`
- appended blocks are concatenated onto the existing note document in order
- existing and appended inline formatting is preserved

## Scratchpad Behavior

Scratchpad is stored as a semantic document and no longer uses markdown H1
synthesis. The scratchpad title is kept as a plain paragraph block, and the
scripts return canonical `document` data plus derived `plain_text`.
