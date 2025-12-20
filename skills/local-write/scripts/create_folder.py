#!/usr/bin/env python3
"""
Create Local Folder

Create a new folder in the local documents directory.
"""

import sys
import json
import argparse
from pathlib import Path
from typing import Dict, Any


# Base documents directory
DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"


def validate_path(relative_path: str) -> Path:
    """
    Validate that the path is safe and within documents folder.

    Args:
        relative_path: Relative path from documents base

    Returns:
        Absolute Path object

    Raises:
        ValueError: If path is invalid or escapes documents folder
    """
    # Convert to Path and resolve
    full_path = (DOCUMENTS_BASE / relative_path).resolve()

    # Check that resolved path is within documents base
    try:
        full_path.relative_to(DOCUMENTS_BASE.resolve())
    except ValueError:
        raise ValueError(
            f"Path '{relative_path}' escapes documents folder. "
            f"All paths must be relative to: {DOCUMENTS_BASE}"
        )

    # Reject absolute paths
    if Path(relative_path).is_absolute():
        raise ValueError(
            f"Absolute paths not allowed. Use relative paths only."
        )

    return full_path


def create_folder(folder_path: str) -> Dict[str, Any]:
    """
    Create a folder (and parents if needed) in the documents directory.

    Args:
        folder_path: Relative path for the folder

    Returns:
        Dictionary with folder info

    Raises:
        ValueError: If path is invalid
    """
    # Validate path
    full_path = validate_path(folder_path)

    # Check if already exists
    already_existed = full_path.exists()

    # Create folder (parents=True creates parent folders if needed)
    full_path.mkdir(parents=True, exist_ok=True)

    # Get relative path
    relative_path = full_path.relative_to(DOCUMENTS_BASE)

    return {
        'path': str(full_path),
        'relative_path': str(relative_path),
        'created': True,
        'already_existed': already_existed
    }


def format_human_readable(result: Dict[str, Any]) -> str:
    """
    Format result in human-readable format.

    Args:
        result: Result dictionary from create_folder

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    if result['already_existed']:
        lines.append("FOLDER ALREADY EXISTS")
    else:
        lines.append("FOLDER CREATED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    lines.append(f"Folder: {result['relative_path']}")
    lines.append(f"Full Path: {result['path']}")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for create_folder script."""
    parser = argparse.ArgumentParser(
        description='Create a folder in the local documents directory',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Base Directory: {DOCUMENTS_BASE}

Examples:
  # Create single folder
  %(prog)s "projects"

  # Create nested folders
  %(prog)s "2025/reports/monthly"

  # Create with JSON output
  %(prog)s "archive/2024" --json
        """
    )

    # Required argument
    parser.add_argument(
        'folder_path',
        help='Folder path (relative to documents folder)'
    )

    # Optional arguments
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Create the folder
        result = create_folder(args.folder_path)

        # Output results
        if args.json:
            output = {
                'success': True,
                'data': result
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(result))

        sys.exit(0)

    except ValueError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'ValidationError',
                'message': str(e),
                'suggestions': [
                    'Use relative paths only (no .. or absolute paths)',
                    'Ensure path stays within documents folder',
                    f'Base directory: {DOCUMENTS_BASE}'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'UnexpectedError',
                'message': f'Unexpected error: {str(e)}',
                'suggestions': [
                    'Check the error message for details',
                    'Verify folder permissions',
                    'Ensure documents folder exists'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
