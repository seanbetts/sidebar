#!/bin/bash
set -euo pipefail

# migrate_to_workspace.sh - Migrate documents to /workspace Docker volume
# This script safely migrates existing documents to the workspace volume used by Skills API

OLD_BASE="$HOME/Agent Smith/Documents"
NEW_BASE="/workspace"
CONTAINER_NAME="agent-smith-skills-api-1"

echo "=========================================="
echo "Agent Smith Workspace Migration"
echo "=========================================="
echo ""
echo "This script will migrate your documents to the Docker workspace volume."
echo ""
echo "  Source:      $OLD_BASE"
echo "  Destination: $NEW_BASE (Docker volume)"
echo ""

# Check if old location exists
if [ ! -d "$OLD_BASE" ]; then
    echo "✓ No existing documents found at $OLD_BASE"
    echo "  Nothing to migrate. The workspace is ready to use!"
    exit 0
fi

# Count files in old location (exclude Mac junk files)
OLD_FILE_COUNT=$(find "$OLD_BASE" -type f -not -name ".DS_Store" -not -name "._*" 2>/dev/null | wc -l | tr -d ' ')
echo "Found $OLD_FILE_COUNT files to migrate."
echo ""

# Dry-run option
if [[ "${1:-}" == "--dry-run" ]]; then
    echo "DRY-RUN MODE: Showing what would be migrated..."
    echo ""
    echo "Files that would be copied:"
    find "$OLD_BASE" -type f -not -name ".DS_Store" -not -name "._*" | head -20
    if [ "$OLD_FILE_COUNT" -gt 20 ]; then
        echo "... and $(($OLD_FILE_COUNT - 20)) more files"
    fi
    echo ""
    echo "To perform the actual migration, run without --dry-run"
    exit 0
fi

# Confirm migration
read -p "Proceed with migration? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

echo ""
echo "Starting migration..."
echo ""

# Ensure Skills API container is running
echo "[1/4] Ensuring Skills API container is running..."
if ! docker compose ps skills-api | grep -q "Up"; then
    echo "  Starting skills-api container..."
    docker compose up -d skills-api
    sleep 5
fi
echo "  ✓ Container running"

# Create workspace directory structure with correct ownership
echo ""
echo "[2/4] Creating workspace directory structure..."
docker compose exec -T skills-api mkdir -p /workspace/notes
docker compose exec -T skills-api mkdir -p /workspace/documents
docker compose exec -T skills-api chown -R appuser:appuser /workspace
echo "  ✓ Directories created with correct ownership"

# Copy files to workspace volume using tar piped through docker
echo ""
echo "[3/4] Copying files to workspace volume..."
echo "  Creating tar archive (excluding Mac junk files)..."
tar --exclude='.DS_Store' --exclude='._*' -czf - -C "$OLD_BASE" . | docker compose exec -T skills-api tar -xzf - -C /workspace/documents/ 2>/dev/null
PIPE_STATUS=$?
if [ $PIPE_STATUS -eq 0 ]; then
    echo "  ✓ Files copied"
else
    echo "  ⚠️  Some warnings during copy (likely Mac extended attributes)"
fi
echo "  Setting ownership to appuser..."
docker compose exec -T skills-api chown -R appuser:appuser /workspace
echo "  ✓ Ownership set"

# Verify migration
echo ""
echo "[4/4] Verifying migration..."
NEW_FILE_COUNT=$(docker compose exec -T skills-api find /workspace/documents -type f 2>/dev/null | wc -l | tr -d ' ')
echo "  Files in workspace: $NEW_FILE_COUNT"

if [ "$NEW_FILE_COUNT" -ge "$OLD_FILE_COUNT" ]; then
    echo "  ✓ Migration successful!"
else
    echo "  ⚠️  Warning: File count mismatch"
    echo "     Expected: $OLD_FILE_COUNT"
    echo "     Found:    $NEW_FILE_COUNT"
    echo ""
    echo "  Please verify the migration before deleting source files."
    exit 1
fi

echo ""
echo "=========================================="
echo "Migration Complete!"
echo "=========================================="
echo ""
echo "Files are now in the Docker workspace volume."
echo "You can access them via the Skills API or through the container."
echo ""

# Ask about deleting old location
read -p "Delete original files from $OLD_BASE? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Creating backup archive before deletion..."
    BACKUP_FILE="$HOME/agent-smith-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar --exclude='.DS_Store' --exclude='._*' -czf "$BACKUP_FILE" -C "$HOME" "Agent Smith/Documents"
    echo "  ✓ Backup created: $BACKUP_FILE"

    echo ""
    echo "Deleting original files..."
    rm -rf "$OLD_BASE"
    echo "  ✓ Original files deleted"

    echo ""
    echo "Migration and cleanup complete!"
    echo "Backup available at: $BACKUP_FILE"
else
    echo ""
    echo "Original files kept at: $OLD_BASE"
    echo "You can delete them manually once you've verified the migration."
fi

echo ""
echo "✓ All done!"
