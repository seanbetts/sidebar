---
name: local-write
description: Write operations for local files - create files, update content, create folders. Use when you need to create or modify markdown documents in the local documents folder.
---

# Local Write Skill

Write operations for local file management. This skill provides functionality to create markdown files, update existing content, and create folder structures in the local documents directory.

## Features

- **File Creation**: Create markdown files with initial content
- **File Updates**: Update existing file content (replace or append)
- **Folder Creation**: Create nested folder structures
- **Path Safety**: All operations constrained to documents folder
- **Markdown Focus**: Optimized for markdown files

## Base Directory

All operations are relative to:
```
~/Documents/Agent Smith/Documents/
```

This path is automatically expanded and validated.

## Scripts

### create_file.py

Create a new markdown file with content.

**Usage:**
```bash
python /skills/local-write/scripts/create_file.py FILENAME [OPTIONS]
```

**Required Arguments:**
- `FILENAME` - Name of the file (relative to base directory)

**Options:**
- `--content TEXT` - Initial file content
- `--title TEXT` - Add a markdown title (# Title) at the top
- `--overwrite` - Overwrite if file exists (default: error if exists)
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Create simple file
python create_file.py "notes.md" --content "My notes here"

# Create with title
python create_file.py "project/readme.md" --title "Project README" --content "Description here"

# Create in subfolder (creates folder if needed)
python create_file.py "2025/january/journal.md" --title "January Journal"

# Overwrite existing file
python create_file.py "draft.md" --content "New draft" --overwrite
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "path": "/Users/user/Documents/Agent Smith/Documents/notes.md",
    "relative_path": "notes.md",
    "size": 256,
    "created": true
  }
}
```

### create_folder.py

Create a folder (and parent folders if needed).

**Usage:**
```bash
python /skills/local-write/scripts/create_folder.py FOLDER_PATH [OPTIONS]
```

**Required Arguments:**
- `FOLDER_PATH` - Folder path (relative to base directory)

**Options:**
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Create single folder
python create_folder.py "projects"

# Create nested folders
python create_folder.py "2025/reports/monthly"

# Create with JSON output
python create_folder.py "archive/2024" --json
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "path": "/Users/user/Documents/Agent Smith/Documents/projects",
    "relative_path": "projects",
    "created": true,
    "already_existed": false
  }
}
```

### update_file.py

Update an existing file's content.

**Usage:**
```bash
python /skills/local-write/scripts/update_file.py FILENAME [OPTIONS]
```

**Required Arguments:**
- `FILENAME` - Name of the file to update (relative to base directory)

**Options:**
- `--content TEXT` - New content to add
- `--mode MODE` - Update mode: `replace` (default) or `append`
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Replace entire file content
python update_file.py "notes.md" --content "New content" --mode replace

# Append to file
python update_file.py "journal.md" --content "\n## New Entry\nContent here" --mode append

# Append with JSON output
python update_file.py "log.md" --content "\nNew log entry" --mode append --json
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "path": "/Users/user/Documents/Agent Smith/Documents/notes.md",
    "relative_path": "notes.md",
    "size": 512,
    "mode": "append",
    "updated": true
  }
}
```

## Path Safety

All paths are validated to ensure they stay within the documents folder:
- ✅ `notes.md` → `~/Documents/Agent Smith/Documents/notes.md`
- ✅ `projects/readme.md` → `~/Documents/Agent Smith/Documents/projects/readme.md`
- ❌ `../outside.md` → ERROR: Path escapes documents folder
- ❌ `/etc/passwd` → ERROR: Absolute paths not allowed

## File Organization Tips

**By Date:**
```
2025/
  january/
    journal.md
    notes.md
  february/
    journal.md
```

**By Project:**
```
projects/
  website/
    notes.md
    tasks.md
  api/
    design.md
```

**By Type:**
```
notes/
  daily-notes.md
drafts/
  article-draft.md
archive/
  old-notes.md
```

## Error Handling

- **File Exists**: Error unless `--overwrite` specified
- **Folder Doesn't Exist**: Auto-created when creating files
- **Invalid Path**: Error if path escapes documents folder
- **Permission Denied**: Error with clear message

## Related Skills

- **local-read**: Read files and list directory contents
- **local-search**: Search files by name, content, date
- **local-manage**: Move, rename, delete files

## Best Practices

1. **Use Clear Filenames**: `project-notes.md` not `notes.md`
2. **Organize in Folders**: Group related files
3. **Use Markdown**: Take advantage of markdown formatting
4. **Add Titles**: Use `--title` for automatic h1 headers
5. **Append for Logs**: Use `--mode append` for journal/log files

## Troubleshooting

**File already exists:**
- Use `--overwrite` to replace
- Or use `update_file.py` with `--mode append`

**Permission denied:**
- Check folder permissions
- Ensure documents folder exists and is writable

**Path not found:**
- create_file.py auto-creates parent folders
- Use create_folder.py first for explicit folder creation
