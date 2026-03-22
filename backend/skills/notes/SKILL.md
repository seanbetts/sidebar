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
The assistant-facing Notes tool surface currently supports creating, reading,
listing, organizing, and scratchpad management. In-place note editing is not
currently exposed because the low-level update path still replaces the full
document.

## Scripts

- `save_note_document.py` - Internal primitive for create, full-document replace, or append semantic note documents
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
- `document.blocks` supports `title`, `paragraph`, `heading`, `subheading`,
  `unordered_list`, `ordered_list`, `checklist`, `list_item`, `blockquote`,
  and `code_block`
- block `0` is normalized to `title`
- block `content` is a list of inline segments with `text`, `marks`, and
  optional `link`
- supported inline marks are `bold`, `italic`, `underline`, `strikethrough`,
  and `inline_code`

Titles are derived from the first non-empty projected plain-text line. Literal `#`
prefixes remain part of the title when they are part of the content.

`save_note_document.py --mode update` remains available as an internal
full-document replace primitive. It is not currently exposed as an assistant
tool because it is not a safe patch-style edit operation.

## Append Behavior

Append is currently an internal document-native primitive:

- pass a semantic `document` body to `save_note_document.py --mode append`
- appended blocks are concatenated onto the existing note document in order
- existing and appended inline formatting is preserved
- this is not currently exposed in the assistant-facing Notes tool surface

## Scratchpad Behavior

Scratchpad is stored as a semantic document and no longer uses markdown H1
synthesis. The scratchpad title is kept as block `0` `title`, and the scripts
return canonical `document` data plus derived `plain_text`.
