---
name: local-search
description: Search operations for local files - search by filename or content. Use when you need to find specific markdown documents in the local documents folder.
---

# Local Search Skill

Search operations for local file management. Find files by name patterns or content within the local documents directory.

## Base Directory

`~/Documents/Agent Smith/Documents/`

## Scripts

### search_files.py

Search for files by name or content.

**Usage:**
```bash
python /skills/local-search/scripts/search_files.py [OPTIONS]
```

**Options:**
- `--name PATTERN` - Search filenames (supports wildcards)
- `--content TEXT` - Search file content
- `--extension EXT` - Filter by extension (e.g., "md")
- `--json` - Output JSON format

**Examples:**
```bash
# Find files by name
python search_files.py --name "*journal*"

# Search file content
python search_files.py --content "important note"

# Search markdown files containing text
python search_files.py --content "TODO" --extension "md"
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "query": {"name": "*journal*"},
    "results": [
      {"path": "2025/journal.md", "size": 1024, "matches": null}
    ],
    "count": 1
  }
}
```
