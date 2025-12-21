---
name: local-read
description: Read operations for local files - list files, read content, get file info. Use when you need to explore or read markdown documents in the local documents folder.
---

# Local Read Skill

Read operations for local file management. This skill provides functionality to list files, read content, and get file/folder information from the local documents directory.

## Features

- **File Listing**: List files in directories with filtering
- **File Reading**: Read file content safely
- **File Info**: Get metadata (size, dates, type)
- **Path Safety**: All operations constrained to documents folder
- **Markdown Focus**: Optimized for markdown documents

## Base Directory

All operations are relative to:
```
~/Documents/Agent Smith/Documents/
```

This path is automatically expanded and validated.

## Scripts

### list_files.py

List files in a directory.

**Usage:**
```bash
python /skills/local-read/scripts/list_files.py [DIRECTORY] [OPTIONS]
```

**Optional Arguments:**
- `DIRECTORY` - Directory to list (relative to base, default: ".")

**Options:**
- `--pattern PATTERN` - Filter by glob pattern (e.g., "*.md")
- `--recursive` - List files recursively
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# List files in root
python list_files.py

# List markdown files
python list_files.py --pattern "*.md"

# List all files recursively
python list_files.py --recursive

# List files in subfolder
python list_files.py "projects" --pattern "*.md" --json
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "directory": "projects",
    "files": [
      {
        "name": "readme.md",
        "path": "projects/readme.md",
        "size": 1024,
        "modified": "2025-12-20T10:30:00",
        "is_file": true
      }
    ],
    "count": 1
  }
}
```

### read_file.py

Read a file's content.

**Usage:**
```bash
python /skills/local-read/scripts/read_file.py FILENAME [OPTIONS]
```

**Required Arguments:**
- `FILENAME` - File to read (relative to base directory)

**Options:**
- `--lines N` - Only read first N lines
- `--json` - Output JSON format (default: raw content)

**Examples:**
```bash
# Read entire file
python read_file.py "notes.md"

# Read first 10 lines
python read_file.py "journal.md" --lines 10

# Read with JSON output
python read_file.py "project/readme.md" --json
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "path": "notes.md",
    "content": "File content here...",
    "size": 256,
    "lines": 15
  }
}
```

### get_info.py

Get file or folder information.

**Usage:**
```bash
python /skills/local-read/scripts/get_info.py PATH [OPTIONS]
```

**Required Arguments:**
- `PATH` - File or folder path (relative to base directory)

**Options:**
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Get file info
python get_info.py "notes.md"

# Get folder info
python get_info.py "projects" --json

# Get info with JSON output
python get_info.py "2025/journal.md" --json
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "path": "notes.md",
    "name": "notes.md",
    "type": "file",
    "size": 1024,
    "created": "2025-12-15T10:00:00",
    "modified": "2025-12-20T10:30:00",
    "is_file": true,
    "is_directory": false
  }
}
```

## Path Safety

All paths are validated to ensure they stay within the documents folder:
- ✅ `notes.md` → `~/Documents/Agent Smith/Documents/notes.md`
- ✅ `projects/readme.md` → Valid subfolder access
- ❌ `../outside.md` → ERROR: Path escapes documents folder
- ❌ `/etc/passwd` → ERROR: Absolute paths not allowed

## Common Use Cases

**Browse files:**
```bash
# See what's in your documents
python list_files.py --recursive

# Find all markdown files
python list_files.py --pattern "*.md" --recursive
```

**Read notes:**
```bash
# Read today's journal
python read_file.py "2025/december/journal.md"

# Preview file (first 20 lines)
python read_file.py "long-document.md" --lines 20
```

**Check file details:**
```bash
# When was this file last modified?
python get_info.py "important-notes.md"

# How big is this folder?
python get_info.py "projects"
```

## Error Handling

- **File Not Found**: Clear error if file/folder doesn't exist
- **Invalid Path**: Error if path escapes documents folder
- **Permission Denied**: Error with clear message

## Related Skills

- **local-write**: Create and update files
- **local-search**: Search files by name/content
- **local-manage**: Move, rename, delete files

## Best Practices

1. **Use Relative Paths**: Always use paths relative to documents base
2. **Check Files First**: Use list_files.py to see what's available
3. **Preview Large Files**: Use --lines to preview before reading all
4. **Organize Well**: Use folders to keep files organized

## Troubleshooting

**File not found:**
- Check path is correct relative to documents base
- Use list_files.py to see available files
- Verify file exists in ~/Documents/Agent Smith/Documents/

**Permission denied:**
- Check file/folder permissions
- Ensure documents folder is readable

**Path error:**
- Don't use .. or absolute paths
- All paths must be relative to documents folder
