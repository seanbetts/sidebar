#!/usr/bin/env python3
"""
Get File/Directory Info

Get metadata about a file or directory in workspace.
"""

import sys
import json
import os
import argparse
from pathlib import Path
from datetime import datetime
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


def get_info(path: str) -> Dict[str, Any]:
    """
    Get file or directory metadata.

    Args:
        path: Path relative to workspace

    Returns:
        Dictionary with metadata

    Raises:
        ValueError: If path is invalid
        FileNotFoundError: If path doesn't exist
    """
    file_path = validate_path(path)

    if not file_path.exists():
        raise FileNotFoundError(f"Path not found: {path}")

    stats = file_path.stat()

    info = {
        'path': str(file_path.relative_to(WORKSPACE_BASE)),
        'name': file_path.name,
        'is_file': file_path.is_file(),
        'is_directory': file_path.is_dir(),
        'size': stats.st_size,
        'created': datetime.fromtimestamp(stats.st_ctime).isoformat(),
        'modified': datetime.fromtimestamp(stats.st_mtime).isoformat(),
        'accessed': datetime.fromtimestamp(stats.st_atime).isoformat(),
    }

    if file_path.is_file():
        info['extension'] = file_path.suffix
        # Try to read line count for text files
        try:
            content = file_path.read_text(encoding='utf-8')
            info['lines'] = len(content.splitlines())
        except:
            info['lines'] = None

    return info


def main():
    """Main entry point for info script."""
    parser = argparse.ArgumentParser(
        description='Get file/directory metadata from workspace'
    )

    parser.add_argument(
        'path',
        help='Path to inspect (relative to workspace)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        result = get_info(args.path)

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileNotFoundError) as e:
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
