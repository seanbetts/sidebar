# Workspace Migration Guide

This guide explains how to migrate your existing documents from `~/Documents/Agent Smith/Documents` to the Docker `/workspace` volume.

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

1. **Checks source**: Verifies `~/Documents/Agent Smith/Documents` exists
2. **Counts files**: Shows how many files will be migrated
3. **Starts container**: Ensures Skills API is running
4. **Creates structure**: Sets up `/workspace/notes` and `/workspace/documents`
5. **Copies files**: Uses `docker cp` to transfer files to the volume
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

# 3. Copy files to workspace
docker cp "$HOME/Documents/Agent Smith/Documents/." agent-smith-skills-api-1:/workspace/documents/

# 4. Verify migration
docker compose exec skills-api ls -la /workspace/documents/

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
ls -lh ~/Documents/agent-smith-backup-*.tar.gz

# 2. Extract backup
tar -xzf ~/Documents/agent-smith-backup-20241220-*.tar.gz -C ~/Documents/

# 3. Your files are restored to ~/Documents/Agent Smith/Documents/
```

## Troubleshooting

### Container not running

```bash
doppler run -- docker compose up -d skills-api
```

### File count mismatch

The script will warn you if counts don't match. Check:

```bash
# Check source
find "$HOME/Documents/Agent Smith/Documents" -type f | wc -l

# Check destination
docker compose exec skills-api find /workspace -type f | wc -l
```

### Permission errors

Ensure you have permission to read source files and the Docker daemon is running.

### Workspace volume issues

```bash
# Inspect volume
docker volume inspect agent-smith_workspace

# List volume contents
docker compose exec skills-api ls -la /workspace/
```

## FAQ

**Q: Will this delete my original files?**
A: Only if you confirm the deletion prompt after successful migration. A backup is created first.

**Q: Can I migrate multiple times?**
A: Yes, but it will overwrite existing files in /workspace. Use dry-run to check first.

**Q: What if I have files in both locations?**
A: The migration will merge them. Newer files will overwrite older ones with the same name.

**Q: Can I access /workspace from my Mac?**
A: Yes, via Docker commands or by mounting the volume. The Skills API provides the primary interface.

**Q: What happens to my old local-* skills?**
A: They'll continue to work with ~/Documents. The new fs skills work with /workspace. You can use both during transition.
