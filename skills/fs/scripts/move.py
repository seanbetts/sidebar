#!/usr/bin/env python3
"""
Move File or Directory in Workspace

Move files or directories within workspace with optional dry-run support.
"""

import sys
import json
import os
import argparse
import shutil
from pathlib import Path
from typing import Dict, Any

# Base workspace directory
WORKSPACE_BASE = Path(os.getenv("WORKSPACE_BASE", "/workspace"))


def validate_path(relative_path: str) -> Path:
    """
    Validate that the path is safe and within workspace folder.

    Args:
        relative_path: Relative path from workspace base

    Returns:
        Absolute Path object

    Raises:
        ValueError: If path is invalid or escapes workspace folder
    """
    # Reject path traversal attempts
    if ".." in relative_path:
        raise ValueError(f"Path traversal not allowed: {relative_path}")

    # Convert to Path and resolve
    full_path = (WORKSPACE_BASE / relative_path).resolve()

    # Check that resolved path is within workspace base
    try:
        full_path.relative_to(WORKSPACE_BASE.resolve())
    except ValueError:
        raise ValueError(
            f"Path '{relative_path}' resolves to a location outside workspace"
        )

    # Reject absolute paths in the original input
    if Path(relative_path).is_absolute():
        raise ValueError("Absolute paths not allowed")

    return full_path


def move_path(
    source: str,
    destination: str,
    dry_run: bool = False
) -> Dict[str, Any]:
    """
    Move a file or directory to a new location.

    Args:
        source: Source path relative to workspace
        destination: Destination path relative to workspace
        dry_run: If True, validate but don't actually move

    Returns:
        Dictionary with operation result

    Raises:
        ValueError: If paths are invalid
        FileNotFoundError: If source doesn't exist
        FileExistsError: If destination already exists
    """
    source_path = validate_path(source)
    dest_path = validate_path(destination)

    if not source_path.exists():
        raise FileNotFoundError(f"Source not found: {source}")

    if dest_path.exists():
        raise FileExistsError(f"Destination already exists: {destination}")

    # Get file/directory type and size
    is_directory = source_path.is_dir()
    if is_directory:
        # Count items in directory
        item_count = sum(1 for _ in source_path.rglob('*'))
        size_info = f"{item_count} items"
    else:
        size_info = f"{source_path.stat().st_size} bytes"

    if dry_run:
        return {
            "success": True,
            "dry_run": True,
            "data": {
                "source": source,
                "destination": destination,
                "type": "directory" if is_directory else "file",
                "size": size_info,
                "message": f"Would move {source} to {destination}"
            }
        }

    # Create parent directory if needed
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    # Move the file or directory
    shutil.move(str(source_path), str(dest_path))

    return {
        "success": True,
        "data": {
            "source": source,
            "destination": destination,
            "type": "directory" if is_directory else "file",
            "size": size_info,
            "message": f"Moved {source} to {destination}"
        }
    }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Move file or directory within workspace"
    )
    parser.add_argument("source", help="Source path (relative to workspace)")
    parser.add_argument("destination", help="Destination path (relative to workspace)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate but don't actually move"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output result as JSON"
    )

    args = parser.parse_args()

    try:
        result = move_path(args.source, args.destination, args.dry_run)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(f"✓ {result['data']['message']}")

        sys.exit(0)

    except (ValueError, FileNotFoundError, FileExistsError) as e:
        error = {"success": False, "error": str(e)}

        if args.json:
            print(json.dumps(error, indent=2), file=sys.stderr)
        else:
            print(f"✗ Error: {e}", file=sys.stderr)

        sys.exit(1)

    except Exception as e:
        error = {"success": False, "error": f"Unexpected error: {str(e)}"}

        if args.json:
            print(json.dumps(error, indent=2), file=sys.stderr)
        else:
            print(f"✗ Unexpected error: {e}", file=sys.stderr)

        sys.exit(1)


if __name__ == "__main__":
    main()
