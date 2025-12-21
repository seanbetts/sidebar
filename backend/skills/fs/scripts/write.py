#!/usr/bin/env python3
"""
Write File to Workspace

Create or update files in workspace with multiple modes.
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


def write_file(
    filename: str,
    content: str,
    mode: str = "replace"
) -> Dict[str, Any]:
    """
    Write content to a file.

    Args:
        filename: File path relative to workspace
        content: Content to write
        mode: Write mode - "create", "replace", or "append"

    Returns:
        Dictionary with operation result

    Raises:
        ValueError: If path is invalid or mode is invalid
        FileExistsError: If mode is "create" and file exists
        FileNotFoundError: If mode is "append" and file doesn't exist
    """
    file_path = validate_path(filename)

    # Validate mode
    if mode not in ["create", "replace", "append"]:
        raise ValueError(f"Invalid mode: {mode}. Must be create, replace, or append")

    # Check file existence based on mode
    exists = file_path.exists()

    if mode == "create" and exists:
        raise FileExistsError(f"File already exists: {filename}")

    # Create parent directories if needed
    file_path.parent.mkdir(parents=True, exist_ok=True)

    # Write content based on mode
    if mode == "append":
        # Append to existing file or create new
        with open(file_path, 'a', encoding='utf-8') as f:
            f.write(content)
        action = "appended" if exists else "created"
    else:
        # Create or replace
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        action = "created" if not exists else "updated"

    return {
        'path': str(file_path.relative_to(WORKSPACE_BASE)),
        'action': action,
        'size': file_path.stat().st_size,
        'lines': len(content.splitlines())
    }


def main():
    """Main entry point for write script."""
    parser = argparse.ArgumentParser(
        description='Write file content to workspace'
    )

    parser.add_argument(
        'filename',
        help='File to write (relative to workspace)'
    )
    parser.add_argument(
        '--content',
        required=True,
        help='Content to write to file'
    )
    parser.add_argument(
        '--mode',
        default='replace',
        choices=['create', 'replace', 'append'],
        help='Write mode: create (fail if exists), replace (default), or append'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        result = write_file(args.filename, args.content, args.mode)

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileExistsError, FileNotFoundError) as e:
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
