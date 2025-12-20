---
name: fs
description: Comprehensive filesystem operations for workspace - list, read, write, delete, move, search files. Use for all file management tasks in /workspace.
capabilities:
  reads: true
  writes: true
  network: false
  external_apis: false
---

# Filesystem Operations (fs)

Complete filesystem CRUD operations for Agent Smith workspace.

## Base Directory

All operations relative to `/workspace` (Docker volume).

## Scripts

- `list.py` - List files with filtering
- `read.py` - Read file content
- `write.py` - Create/update files
- `info.py` - Get file metadata
- `mkdir.py` - Create directories
- `delete.py` - Delete files/folders
- `move.py` - Move files
- `rename.py` - Rename files
- `copy.py` - Copy files
- `search.py` - Search by name/content

All scripts support `--json` flag for structured output.

## Security

- Path validation prevents traversal outside /workspace
- Write operations restricted to allowlist paths
- All paths are relative to WORKSPACE_BASE environment variable
