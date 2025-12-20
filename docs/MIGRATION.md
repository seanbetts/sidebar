# Workspace Migration Guide

This guide explains how to migrate your existing documents from `~/Agent Smith/Documents` to the Docker workspace volume.

## Why Migrate?

The OpenWebUI integration uses a Docker volume (`/workspace`) for all file operations. Migrating your existing documents ensures:

- **Unified access**: All skills access the same workspace
- **Docker isolation**: Files are managed within the container environment
- **Backup safety**: Original files are archived before deletion
- **Skills compatibility**: New fs and notes skills work with /workspace

## Migration Script

The migration script is located at `scripts/migrate_to_workspace.sh`.

### Usage

```bash
# Dry-run: See what would be migrated without making changes
./scripts/migrate_to_workspace.sh --dry-run

# Actual migration: Migrate files and optionally delete originals
./scripts/migrate_to_workspace.sh
```

### What It Does

1. **Checks source**: Verifies `~/Agent Smith/Documents` exists
2. **Counts files**: Shows how many files will be migrated
3. **Starts container**: Ensures Skills API is running
4. **Creates structure**: Sets up `/workspace/notes` and `/workspace/documents`
5. **Copies files**: Pipes tar through docker to copy with correct ownership (excludes .DS_Store)
6. **Verifies**: Confirms file count matches
7. **Backup & cleanup**: Optionally creates tar.gz backup and deletes originals

### Safety Features

- **Dry-run mode**: Preview migration without making changes
- **Confirmation prompts**: Asks before migrating and before deleting
- **Automatic backup**: Creates timestamped tar.gz archive before deletion
- **Verification**: Checks file count before allowing deletion
- **No data loss**: Original files only deleted after successful migration

## Manual Migration

If you prefer to migrate manually:

```bash
# 1. Start Skills API container
doppler run -- docker compose up -d skills-api

# 2. Create workspace directories
docker compose exec skills-api mkdir -p /workspace/documents
docker compose exec skills-api mkdir -p /workspace/notes

# 3. Copy files to workspace (excluding .DS_Store, as appuser)
cd "$HOME/Agent Smith/Documents"
tar --exclude='.DS_Store' -czf - . | docker compose exec -T -u appuser skills-api tar -xzf - -C /workspace/documents/

# 4. Verify migration
docker compose exec skills-api find /workspace/documents -type f | wc -l

# 5. Test access via Skills API
doppler run -- python3 tests/test_mcp_client.py
```

## Post-Migration

After migration, you can:

1. **Access files via MCP tools**:
   - `fs_list` - List files in workspace
   - `fs_read` - Read file contents
   - `fs_write` - Write new files
   - `fs_delete` - Delete files

2. **Create notes**:
   - `notes_create` - Create new markdown notes
   - `notes_update` - Update existing notes
   - `notes_append` - Append to notes

3. **Use OpenWebUI** (Phase 7):
   - Chat interface with Skills API integration
   - Visual file browser
   - Note-taking interface

## Rollback

If you need to rollback:

```bash
# 1. Find your backup
ls -lh ~/agent-smith-backup-*.tar.gz

# 2. Extract backup
tar -xzf ~/agent-smith-backup-20241220-*.tar.gz -C ~/

# 3. Your files are restored to ~/Agent Smith/Documents/
```

## Troubleshooting

### Container not running

```bash
doppler run -- docker compose up -d skills-api
```

### File count mismatch

The script will warn you if counts don't match. Check:

```bash
# Check source (excluding .DS_Store)
find "$HOME/Agent Smith/Documents" -type f -not -name ".DS_Store" | wc -l

# Check destination
docker compose exec skills-api find /workspace/documents -type f | wc -l
```

### Permission errors

Ensure you have permission to read source files and the Docker daemon is running.

### Workspace volume issues

```bash
# Inspect volume
docker volume inspect agent-smith_workspace

# List volume contents
docker compose exec skills-api ls -la /workspace/documents/

# Check file ownership (should be appuser:appuser)
docker compose exec skills-api ls -ln /workspace/documents/
```

## FAQ

**Q: Will this delete my original files?**
A: Only if you confirm the deletion prompt after successful migration. A backup is created first.

**Q: Can I migrate multiple times?**
A: Yes, but it will overwrite existing files in /workspace. Use dry-run to check first.

**Q: What if I have files in both locations?**
A: The migration will merge them. Tar will overwrite files with the same name.

**Q: Can I access /workspace from my Mac?**
A: Yes, via Docker commands or the Skills API. The volume is managed by Docker but accessible through the container.

**Q: What happens to my old local-* skills?**
A: They'll continue to work with ~/Agent Smith/Documents. The new fs skills work with /workspace. You can use both during transition.

**Q: How are permissions handled?**
A: Files are copied as the appuser (uid 1000) to ensure the Skills API can read and write them properly.
