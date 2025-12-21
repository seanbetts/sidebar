#!/usr/bin/env python3
"""
Read File from Workspace

Read file content with optional line range support.
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


def read_file(
    filename: str,
    offset: int = 0,
    lines: int = None
) -> Dict[str, Any]:
    """
    Read file content with optional line range.

    Args:
        filename: File path relative to workspace
        offset: Starting line number (0-indexed)
        lines: Number of lines to read (None = all)

    Returns:
        Dictionary with file content and metadata

    Raises:
        ValueError: If path is invalid
        FileNotFoundError: If file doesn't exist
    """
    file_path = validate_path(filename)

    if not file_path.exists():
        raise FileNotFoundError(f"File not found: {filename}")

    if not file_path.is_file():
        raise ValueError(f"Path is not a file: {filename}")

    # Read file content
    content = file_path.read_text(encoding='utf-8')
    content_lines = content.splitlines(keepends=True)

    # Apply offset and line limit
    if offset > 0:
        content_lines = content_lines[offset:]

    if lines is not None:
        content_lines = content_lines[:lines]

    filtered_content = ''.join(content_lines)

    return {
        'path': str(file_path.relative_to(WORKSPACE_BASE)),
        'content': filtered_content,
        'size': file_path.stat().st_size,
        'total_lines': len(content.splitlines()),
        'returned_lines': len(filtered_content.splitlines())
    }


def main():
    """Main entry point for read script."""
    parser = argparse.ArgumentParser(
        description='Read file content from workspace'
    )

    parser.add_argument(
        'filename',
        help='File to read (relative to workspace)'
    )
    parser.add_argument(
        '--offset',
        type=int,
        default=0,
        help='Starting line number (0-indexed, default: 0)'
    )
    parser.add_argument(
        '--lines',
        type=int,
        help='Number of lines to read (default: all)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        result = read_file(args.filename, args.offset, args.lines)

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
