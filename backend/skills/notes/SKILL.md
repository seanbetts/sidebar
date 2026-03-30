---
name: notes
description: Notes operations backed by the database - create, edit, read, list, move, pin, archive, delete notes and folders, plus scratchpad management.
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
editing, listing, organizing, and scratchpad management through a structured
block-level edit contract.

## Scripts

- `save_note_document.py` - Internal primitive for create, full-document replace, or append semantic note documents
- `edit_note.py` - Assistant-facing structured block edit entry point
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

- `document.version` is currently `2`
- `document.blocks` supports `title`, `paragraph`, `heading`, `subheading`,
  `unordered_list`, `ordered_list`, `checklist`, `list_item`, `blockquote`,
  and `code_block`
- block `0` is normalized to `title`
- container blocks use `children`, not `content`
- `unordered_list`, `ordered_list`, and `checklist` contain `children` made of
  `list_item` blocks
- `blockquote` contains `children` made of body blocks such as `paragraph`,
  `heading`, `subheading`, lists, or `code_block`
- do not emit top-level `list_item` blocks, wrap them in a list container
- block `content` is a list of inline segments with `text`, `marks`, and
  optional `link`
- supported inline marks are `bold`, `italic`, `underline`, `strikethrough`,
  and `inline_code`

Canonical example:

```json
{
  "version": 2,
  "blocks": [
    {
      "type": "title",
      "content": [{"text": "Q2 AI Strategy", "marks": []}]
    },
    {
      "type": "unordered_list",
      "children": [
        {
          "type": "list_item",
          "content": [{"text": "Activation at scale", "marks": ["bold"]}]
        },
        {
          "type": "list_item",
          "content": [{"text": "Measurement reinvention", "marks": []}]
        }
      ]
    },
    {
      "type": "blockquote",
      "children": [
        {
          "type": "paragraph",
          "content": [{"text": "The workflow layer is the moat.", "marks": []}]
        }
      ]
    },
    {
      "type": "paragraph",
      "content": [{"text": "Next step: align with regional MDs.", "marks": []}]
    }
  ]
}
```

Invalid shape to avoid:
- do not send a top-level `list_item`
- do not send `blockquote.content`, use `blockquote.children`

Titles are derived from the first non-empty projected plain-text line. Literal `#`
prefixes remain part of the title when they are part of the content.

## Assistant Edit Note Contract

`edit_note.py` is the assistant-facing edit path for existing notes.

- pass `note_id`
- pass `expected_updated_at` as the exact `updated_at` string returned by
  `Get Note`
- pass ordered `operations`

Supported operations:

- `rename_note_title`
- `replace_block`
- `insert_blocks_after`
- `delete_block`

Guardrails:

- only `rename_note_title` may modify block `0`
- `replace_block` and `delete_block` only apply to indices `>= 1`
- inserted and replacement blocks must be body blocks, never `title`
- the whole edit is atomic and fails on stale `expected_updated_at`

`save_note_document.py --mode update` remains available as an internal
full-document replace primitive. It is not the assistant-facing note edit tool.

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
