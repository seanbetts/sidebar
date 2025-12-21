#!/bin/bash
set -euo pipefail

# sync_workspace_view.sh - Sync Docker workspace to local folder for viewing
# This creates a read-only copy of the workspace you can browse in Finder

LOCAL_VIEW="$HOME/Agent Smith/workspace-view"
CONTAINER_NAME="agent-smith-skills-api-1"

echo "=========================================="
echo "Workspace Sync (Docker → Finder)"
echo "=========================================="
echo ""
echo "  Source:      Docker volume (agent-smith_workspace)"
echo "  Destination: $LOCAL_VIEW"
echo ""

# Create local directory
mkdir -p "$LOCAL_VIEW"

# Check if container is running
if ! docker compose ps skills-api | grep -q "Up"; then
    echo "❌ Skills API container is not running"
    echo "   Start it with: doppler run -- docker compose up -d skills-api"
    exit 1
fi

echo "Syncing workspace contents..."
echo ""

# Copy from Docker volume to local folder
docker cp "$CONTAINER_NAME:/workspace/." "$LOCAL_VIEW/"

echo "✓ Sync complete!"
echo ""
echo "=========================================="
echo "View your workspace in Finder:"
echo "=========================================="
echo ""
echo "  $LOCAL_VIEW"
echo ""
echo "Note: This is a READ-ONLY copy for viewing."
echo "To make changes, use the MCP tools or edit in the container."
echo ""
echo "Run this script again to refresh the view."
echo ""

# Optionally open in Finder
read -p "Open in Finder now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "$LOCAL_VIEW"
fi
