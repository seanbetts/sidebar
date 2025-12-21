#!/usr/bin/env python3
"""
Create Directory in Workspace

Create a new directory in workspace.
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


def create_directory(
    path: str,
    parents: bool = True,
    exist_ok: bool = False
) -> Dict[str, Any]:
    """
    Create a directory.

    Args:
        path: Directory path relative to workspace
        parents: Create parent directories if needed
        exist_ok: Don't error if directory already exists

    Returns:
        Dictionary with operation result

    Raises:
        ValueError: If path is invalid
        FileExistsError: If directory exists and exist_ok is False
    """
    dir_path = validate_path(path)

    if dir_path.exists() and not exist_ok:
        raise FileExistsError(f"Directory already exists: {path}")

    # Create directory
    dir_path.mkdir(parents=parents, exist_ok=exist_ok)

    return {
        'path': str(dir_path.relative_to(WORKSPACE_BASE)),
        'action': 'created' if not dir_path.exists() else 'already_exists'
    }


def main():
    """Main entry point for mkdir script."""
    parser = argparse.ArgumentParser(
        description='Create directory in workspace'
    )

    parser.add_argument(
        'path',
        help='Directory to create (relative to workspace)'
    )
    parser.add_argument(
        '--no-parents',
        action='store_true',
        help='Do not create parent directories'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        result = create_directory(
            args.path,
            parents=not args.no_parents,
            exist_ok=True
        )

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileExistsError) as e:
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
