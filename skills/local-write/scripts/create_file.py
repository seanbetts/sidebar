#!/usr/bin/env python3
"""
Create Local File

Create a new markdown file in the local documents folder.
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


def create_file(
    filename: str,
    content: str = "",
    title: str = None,
    overwrite: bool = False
) -> Dict[str, Any]:
    """
    Create a new file in the documents folder.

    Args:
        filename: Relative path for the file
        content: Initial file content
        title: Optional markdown title to add at top
        overwrite: If True, overwrite existing file

    Returns:
        Dictionary with file info

    Raises:
        ValueError: If path is invalid
        FileExistsError: If file exists and overwrite=False
    """
    # Validate path
    file_path = validate_path(filename)

    # Check if file exists
    if file_path.exists() and not overwrite:
        raise FileExistsError(
            f"File already exists: {filename}. Use --overwrite to replace."
        )

    # Create parent directories if needed
    file_path.parent.mkdir(parents=True, exist_ok=True)

    # Build content
    full_content = ""
    if title:
        full_content = f"# {title}\n\n"
    full_content += content

    # Write file
    file_path.write_text(full_content, encoding='utf-8')

    # Get file info
    file_size = file_path.stat().st_size
    relative_path = file_path.relative_to(DOCUMENTS_BASE)

    return {
        'path': str(file_path),
        'relative_path': str(relative_path),
        'size': file_size,
        'created': True
    }


def format_human_readable(result: Dict[str, Any]) -> str:
    """
    Format result in human-readable format.

    Args:
        result: Result dictionary from create_file

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("FILE CREATED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    lines.append(f"File: {result['relative_path']}")
    lines.append(f"Full Path: {result['path']}")
    lines.append(f"Size: {result['size']} bytes")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for create_file script."""
    parser = argparse.ArgumentParser(
        description='Create a new file in the local documents folder',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Base Directory: {DOCUMENTS_BASE}

Examples:
  # Create simple file
  %(prog)s "notes.md" --content "My notes here"

  # Create with title
  %(prog)s "project/readme.md" --title "Project README" --content "Description"

  # Create in subfolder (creates folder if needed)
  %(prog)s "2025/january/journal.md" --title "January Journal"
        """
    )

    # Required argument
    parser.add_argument(
        'filename',
        help='Name of the file (relative to documents folder)'
    )

    # Optional arguments
    parser.add_argument(
        '--content',
        default='',
        help='Initial file content'
    )
    parser.add_argument(
        '--title',
        help='Add a markdown title (# Title) at the top'
    )
    parser.add_argument(
        '--overwrite',
        action='store_true',
        help='Overwrite if file exists (default: error if exists)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Create the file
        result = create_file(
            filename=args.filename,
            content=args.content,
            title=args.title,
            overwrite=args.overwrite
        )

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

    except FileExistsError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'FileExistsError',
                'message': str(e),
                'suggestions': [
                    'Use --overwrite to replace the existing file',
                    'Choose a different filename',
                    'Use update_file.py to modify existing file'
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
                    'Verify file permissions',
                    'Ensure documents folder exists'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
