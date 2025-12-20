#!/usr/bin/env python3
"""
Update Local File

Update an existing file's content (replace or append).
"""

import sys
import json
import argparse
import yaml
from pathlib import Path
from typing import Dict, Any


# Base documents directory
DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"
CONFIG_FILE = Path.home() / ".agent-smith" / "folder_config.yaml"


def resolve_alias(path: str) -> str:
    """Resolve @alias in path to actual folder path."""
    if not path.startswith('@'):
        return path
    parts = path[1:].split('/', 1)
    alias = parts[0]
    remainder = parts[1] if len(parts) > 1 else ""
    if not CONFIG_FILE.exists():
        raise ValueError(f"Folder configuration not found. Run: python /skills/folder-config/scripts/init_config.py")
    with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    if not config or 'aliases' not in config:
        raise ValueError(f"Invalid folder configuration: {CONFIG_FILE}")
    if alias not in config['aliases']:
        available = ', '.join(f"@{a}" for a in sorted(config['aliases'].keys()))
        raise ValueError(f"Alias '@{alias}' not found. Available aliases: {available}")
    folder_path = config['aliases'][alias]
    if remainder:
        return f"{folder_path}/{remainder}"
    return folder_path


def validate_path(relative_path: str) -> Path:
    """
    Validate that the path is safe and within documents folder.
    Supports @alias syntax for folder shortcuts.

    Args:
        relative_path: Relative path from documents base (may include @alias)

    Returns:
        Absolute Path object

    Raises:
        ValueError: If path is invalid or escapes documents folder
    """
    # Resolve any @alias in the path
    resolved_path = resolve_alias(relative_path)

    # Convert to Path and resolve
    full_path = (DOCUMENTS_BASE / resolved_path).resolve()

    # Check that resolved path is within documents base
    try:
        full_path.relative_to(DOCUMENTS_BASE.resolve())
    except ValueError:
        raise ValueError(
            f"Path '{relative_path}' resolves to a location outside documents folder. "
            f"All paths must be relative to: {DOCUMENTS_BASE}"
        )

    # Reject absolute paths in the original input (after alias resolution)
    if Path(resolved_path).is_absolute():
        raise ValueError(
            f"Absolute paths not allowed. Use relative paths or @alias syntax."
        )

    return full_path


def update_file(
    filename: str,
    content: str,
    mode: str = 'replace'
) -> Dict[str, Any]:
    """
    Update an existing file's content.

    Args:
        filename: Relative path for the file
        content: New content to write
        mode: 'replace' to replace entire file, 'append' to add to end

    Returns:
        Dictionary with file info

    Raises:
        ValueError: If path is invalid or mode is invalid
        FileNotFoundError: If file doesn't exist
    """
    # Validate mode
    if mode not in ['replace', 'append']:
        raise ValueError(f"Invalid mode: {mode}. Must be 'replace' or 'append'")

    # Validate path
    file_path = validate_path(filename)

    # Check if file exists
    if not file_path.exists():
        raise FileNotFoundError(
            f"File not found: {filename}. Use create_file.py to create new files."
        )

    # Update based on mode
    if mode == 'replace':
        file_path.write_text(content, encoding='utf-8')
    else:  # append
        existing_content = file_path.read_text(encoding='utf-8')
        file_path.write_text(existing_content + content, encoding='utf-8')

    # Get file info
    file_size = file_path.stat().st_size
    relative_path = file_path.relative_to(DOCUMENTS_BASE)

    return {
        'path': str(file_path),
        'relative_path': str(relative_path),
        'size': file_size,
        'mode': mode,
        'updated': True
    }


def format_human_readable(result: Dict[str, Any]) -> str:
    """
    Format result in human-readable format.

    Args:
        result: Result dictionary from update_file

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("FILE UPDATED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    lines.append(f"File: {result['relative_path']}")
    lines.append(f"Full Path: {result['path']}")
    lines.append(f"Mode: {result['mode']}")
    lines.append(f"New Size: {result['size']} bytes")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for update_file script."""
    parser = argparse.ArgumentParser(
        description='Update an existing file in the local documents folder',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Base Directory: {DOCUMENTS_BASE}

Examples:
  # Replace entire file content
  %(prog)s "notes.md" --content "New content" --mode replace

  # Append to file
  %(prog)s "journal.md" --content "\\n## New Entry\\nContent" --mode append

  # Append with JSON output
  %(prog)s "log.md" --content "\\nNew log entry" --mode append --json
        """
    )

    # Required arguments
    parser.add_argument(
        'filename',
        help='Name of the file to update (relative to documents folder)'
    )

    # Optional arguments
    parser.add_argument(
        '--content',
        required=True,
        help='New content to add'
    )
    parser.add_argument(
        '--mode',
        choices=['replace', 'append'],
        default='replace',
        help='Update mode: replace (default) or append'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Update the file
        result = update_file(
            filename=args.filename,
            content=args.content,
            mode=args.mode
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
                    'Mode must be "replace" or "append"',
                    f'Base directory: {DOCUMENTS_BASE}'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except FileNotFoundError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'FileNotFoundError',
                'message': str(e),
                'suggestions': [
                    'Use create_file.py to create new files',
                    'Check that the filename is correct',
                    'Verify the file exists in the documents folder'
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
