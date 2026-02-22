---
name: files
description: Filesystem operations backed by ingestion - list, read, write, rename, pin, delete, and search files. Use for file management tasks in storage.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Filesystem Operations (files)

Filesystem operations for ingestion-backed files.

## Base Directory

All operations are relative to the ingestion-backed storage root.

## Scripts

- `list.py` - List files with filtering
- `read.py` - Read file content
- `write.py` - Create/update files
- `delete.py` - Delete files/folders
- `rename.py` - Rename files
- `pin.py` - Pin or unpin files
- `search.py` - Search by name/content

Compatibility scripts retained for MCP flows:
- `copy.py` - Copy files/folders
- `move.py` - Move files/folders

All scripts support `--json` flag for structured output.

## Security

- Path validation prevents traversal outside storage root
- Access to profile-images is blocked
- All paths are relative to the storage root
