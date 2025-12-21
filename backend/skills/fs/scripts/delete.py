#!/usr/bin/env python3
"""
Delete File/Directory from Workspace

Delete a file or directory from workspace.
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
    """Validate that the path is safe and within workspace folder."""
    if ".." in relative_path:
        raise ValueError(f"Path traversal not allowed: {relative_path}")

    full_path = (WORKSPACE_BASE / relative_path).resolve()

    try:
        full_path.relative_to(WORKSPACE_BASE.resolve())
    except ValueError:
        raise ValueError(
            f"Path '{relative_path}' resolves to a location outside workspace"
        )

    if Path(relative_path).is_absolute():
        raise ValueError("Absolute paths not allowed")

    return full_path


def delete_path(
    path: str,
    recursive: bool = False
) -> Dict[str, Any]:
    """
    Delete a file or directory.

    Args:
        path: Path relative to workspace
        recursive: If True, delete directories recursively

    Returns:
        Dictionary with operation result

    Raises:
        ValueError: If path is invalid
        FileNotFoundError: If path doesn't exist
        OSError: If trying to delete non-empty directory without recursive
    """
    file_path = validate_path(path)

    if not file_path.exists():
        raise FileNotFoundError(f"Path not found: {path}")

    is_file = file_path.is_file()
    is_dir = file_path.is_dir()

    # Delete based on type
    if is_file:
        file_path.unlink()
        item_type = "file"
    elif is_dir:
        if recursive:
            shutil.rmtree(file_path)
        else:
            file_path.rmdir()  # This will fail if directory is not empty
        item_type = "directory"
    else:
        raise ValueError(f"Unknown path type: {path}")

    return {
        'path': str(file_path.relative_to(WORKSPACE_BASE)),
        'type': item_type,
        'action': 'deleted'
    }


def main():
    """Main entry point for delete script."""
    parser = argparse.ArgumentParser(
        description='Delete file or directory from workspace'
    )

    parser.add_argument(
        'path',
        help='Path to delete (relative to workspace)'
    )
    parser.add_argument(
        '--recursive',
        action='store_true',
        help='Delete directories recursively'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        result = delete_path(args.path, args.recursive)

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileNotFoundError, OSError) as e:
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
