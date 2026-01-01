---
name: fs
description: Filesystem operations backed by ingestion - list, read, write, delete, move, search files. Use for file management tasks in storage.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Filesystem Operations (fs)

Filesystem operations for ingestion-backed files.

## Base Directory

All operations are relative to the ingestion-backed storage root.

## Scripts

- `list.py` - List files with filtering
- `read.py` - Read file content
- `write.py` - Create/update files
- `info.py` - Get file metadata
- `delete.py` - Delete files/folders
- `move.py` - Move files
- `rename.py` - Rename files
- `search.py` - Search by name/content

All scripts support `--json` flag for structured output.

## Security

- Path validation prevents traversal outside storage root
- Access to profile-images is blocked
- All paths are relative to the storage root
