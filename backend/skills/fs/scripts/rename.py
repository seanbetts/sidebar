#!/usr/bin/env python3
"""
Rename File or Directory in Workspace

Rename files or directories within workspace (in same directory).
"""

import sys
import json
import os
import argparse
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


def rename_path(
    path: str,
    new_name: str,
    dry_run: bool = False
) -> Dict[str, Any]:
    """
    Rename a file or directory (stays in same directory).

    Args:
        path: Path to file/directory relative to workspace
        new_name: New name (just the name, not full path)
        dry_run: If True, validate but don't actually rename

    Returns:
        Dictionary with operation result

    Raises:
        ValueError: If paths are invalid or new_name contains path separators
        FileNotFoundError: If source doesn't exist
        FileExistsError: If destination already exists
    """
    source_path = validate_path(path)

    if not source_path.exists():
        raise FileNotFoundError(f"Path not found: {path}")

    # Ensure new_name is just a name, not a path
    if "/" in new_name or "\\" in new_name:
        raise ValueError("new_name must be a simple name, not a path")

    # Construct destination path (same parent directory, new name)
    dest_path = source_path.parent / new_name

    # Validate destination is still in workspace
    try:
        dest_path.resolve().relative_to(WORKSPACE_BASE.resolve())
    except ValueError:
        raise ValueError("Rename would escape workspace")

    if dest_path.exists():
        raise FileExistsError(f"A file or directory named '{new_name}' already exists")

    is_directory = source_path.is_dir()
    old_name = source_path.name

    if dry_run:
        return {
            "success": True,
            "dry_run": True,
            "data": {
                "old_name": old_name,
                "new_name": new_name,
                "path": str(source_path.parent.relative_to(WORKSPACE_BASE)),
                "type": "directory" if is_directory else "file",
                "message": f"Would rename '{old_name}' to '{new_name}'"
            }
        }

    # Rename the file or directory
    source_path.rename(dest_path)

    return {
        "success": True,
        "data": {
            "old_name": old_name,
            "new_name": new_name,
            "path": str(source_path.parent.relative_to(WORKSPACE_BASE)),
            "type": "directory" if is_directory else "file",
            "message": f"Renamed '{old_name}' to '{new_name}'"
        }
    }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Rename file or directory within workspace"
    )
    parser.add_argument("path", help="Path to rename (relative to workspace)")
    parser.add_argument("new_name", help="New name (just the name, not a path)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate but don't actually rename"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output result as JSON"
    )

    args = parser.parse_args()

    try:
        result = rename_path(args.path, args.new_name, args.dry_run)

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
