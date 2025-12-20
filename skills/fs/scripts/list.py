#!/usr/bin/env python3
"""
List Files in Workspace

List files in the workspace directory with pattern filtering and recursive option.
"""

import sys
import json
import os
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List

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
        raise ValueError(
            f"Path traversal not allowed: {relative_path}"
        )

    # Convert to Path and resolve
    full_path = (WORKSPACE_BASE / relative_path).resolve()

    # Check that resolved path is within workspace base
    try:
        full_path.relative_to(WORKSPACE_BASE.resolve())
    except ValueError:
        raise ValueError(
            f"Path '{relative_path}' resolves to a location outside workspace. "
            f"All paths must be relative to: {WORKSPACE_BASE}"
        )

    # Reject absolute paths in the original input
    if Path(relative_path).is_absolute():
        raise ValueError(
            f"Absolute paths not allowed. Use relative paths from workspace."
        )

    return full_path


def list_files(
    directory: str = ".",
    pattern: str = "*",
    recursive: bool = False
) -> Dict[str, Any]:
    """
    List files in a directory.

    Args:
        directory: Directory to list (relative to base)
        pattern: Glob pattern to filter files
        recursive: If True, search recursively

    Returns:
        Dictionary with file list and metadata

    Raises:
        ValueError: If path is invalid
        FileNotFoundError: If directory doesn't exist
    """
    # Validate path
    dir_path = validate_path(directory)

    # Check directory exists
    if not dir_path.exists():
        raise FileNotFoundError(f"Directory not found: {directory}")

    if not dir_path.is_dir():
        raise ValueError(f"Path is not a directory: {directory}")

    # List files
    files = []

    if recursive:
        # Recursive search
        for file_path in dir_path.rglob(pattern):
            files.append(file_path)
    else:
        # Non-recursive search
        for file_path in dir_path.glob(pattern):
            files.append(file_path)

    # Sort files by name
    files.sort()

    # Build file info list
    file_list = []
    for file_path in files:
        stats = file_path.stat()
        relative_path = file_path.relative_to(WORKSPACE_BASE)

        file_info = {
            'name': file_path.name,
            'path': str(relative_path),
            'size': stats.st_size,
            'modified': datetime.fromtimestamp(stats.st_mtime).isoformat(),
            'is_file': file_path.is_file(),
            'is_directory': file_path.is_dir()
        }
        file_list.append(file_info)

    relative_dir = dir_path.relative_to(WORKSPACE_BASE)

    return {
        'directory': str(relative_dir),
        'files': file_list,
        'count': len(file_list)
    }


def main():
    """Main entry point for list script."""
    parser = argparse.ArgumentParser(
        description='List files in the workspace directory',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    # Optional arguments
    parser.add_argument(
        'directory',
        nargs='?',
        default='.',
        help='Directory to list (relative to workspace, default: ".")'
    )
    parser.add_argument(
        '--pattern',
        default='*',
        help='Filter by glob pattern (e.g., "*.md")'
    )
    parser.add_argument(
        '--recursive',
        action='store_true',
        help='List files recursively'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # List files
        result = list_files(
            directory=args.directory,
            pattern=args.pattern,
            recursive=args.recursive
        )

        # Output results
        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except ValueError as e:
        error_output = {
            'success': False,
            'error': str(e)
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except FileNotFoundError as e:
        error_output = {
            'success': False,
            'error': str(e)
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            'success': False,
            'error': f'Unexpected error: {str(e)}'
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
