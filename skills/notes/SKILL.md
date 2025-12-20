---
name: notes
description: Create, update, and append markdown notes with automatic organization, metadata, and tagging. Use for quick note-taking with minimal friction.
capabilities:
  reads: false
  writes: true
  network: false
  external_apis: false
---

# Notes Skill

Quick markdown note-taking with intelligent organization and flexible update operations.

## Features

- Three operations: create, update, append
- Auto-organization by date if no folder specified
- YAML frontmatter with title, date, tags
- Workspace-relative paths
- JSON output for automation

## Scripts

### save_markdown.py

Save markdown note with metadata. Supports create/update/append modes.

**Usage:**
```bash
python save_markdown.py "Note Title" --content "Content here" [OPTIONS]
```

**Options:**
- `--mode MODE` - Operation mode: create, update, or append (default: create)
- `--folder FOLDER` - Subfolder in notes/ (default: YYYY/Month)
- `--tags TAGS` - Comma-separated tags
- `--json` - JSON output

**Modes:**
- `create`: Create new note (fails if exists)
- `update`: Replace existing note content (fails if doesn't exist)
- `append`: Append to existing note (creates if doesn't exist)

**Examples:**
```bash
# Create a new note
python save_markdown.py "Meeting Notes" --content "Discussed project timeline" --tags "meeting,project" --json

# Update existing note
python save_markdown.py "Meeting Notes" --content "New content replaces old" --mode update --json

# Append to existing note
python save_markdown.py "Meeting Notes" --content "Additional information" --mode append --json

# Organize in custom folder
python save_markdown.py "Personal Note" --content "Content" --folder "personal" --json
```

## Output

All scripts return JSON with:
- `success`: Boolean indicating success/failure
- `data`: Object with path, title, mode, size
- `error`: Error message if failed
