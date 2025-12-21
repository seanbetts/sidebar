---
name: local-manage
description: Management operations for local files - move, rename, delete, copy files. Use when you need to organize or clean up markdown documents in the local documents folder.
---

# Local Manage Skill

Management operations for local file organization. Move, rename, delete, and copy files within the local documents directory.

## Base Directory

`~/Documents/Agent Smith/Documents/`

## Scripts

### move_file.py
Move a file to a new location.

```bash
python /skills/local-manage/scripts/move_file.py SOURCE DESTINATION [--json]
```

### rename_file.py
Rename a file.

```bash
python /skills/local-manage/scripts/rename_file.py OLD_NAME NEW_NAME [--json]
```

### delete_file.py
Delete a file or folder.

```bash
python /skills/local-manage/scripts/delete_file.py PATH [--recursive] [--json]
```

### copy_file.py
Copy a file.

```bash
python /skills/local-manage/scripts/copy_file.py SOURCE DESTINATION [--json]
```

## Safety

- All paths validated to stay within documents folder
- Delete operations are permanent (no trash/undo)
- Use --recursive carefully with delete_file.py
