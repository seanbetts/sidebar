#!/usr/bin/env python3
"""
List Local Files

List files in the local documents directory.
"""

import sys
import json
import argparse
import yaml
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List


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
        relative_path = file_path.relative_to(DOCUMENTS_BASE)

        file_info = {
            'name': file_path.name,
            'path': str(relative_path),
            'size': stats.st_size,
            'modified': datetime.fromtimestamp(stats.st_mtime).isoformat(),
            'is_file': file_path.is_file(),
            'is_directory': file_path.is_dir()
        }
        file_list.append(file_info)

    relative_dir = dir_path.relative_to(DOCUMENTS_BASE)

    return {
        'directory': str(relative_dir),
        'files': file_list,
        'count': len(file_list)
    }


def format_human_readable(result: Dict[str, Any]) -> str:
    """
    Format result in human-readable format.

    Args:
        result: Result dictionary from list_files

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append(f"FILES IN: {result['directory']}")
    lines.append("=" * 80)
    lines.append("")

    if result['count'] == 0:
        lines.append("No files found.")
    else:
        lines.append(f"Found {result['count']} item(s):\n")

        for file_info in result['files']:
            # Type indicator
            type_indicator = "📁" if file_info['is_directory'] else "📄"

            lines.append(f"{type_indicator} {file_info['name']}")
            lines.append(f"   Path: {file_info['path']}")

            if file_info['is_file']:
                # Show size for files
                size_bytes = file_info['size']
                if size_bytes < 1024:
                    size_str = f"{size_bytes} B"
                elif size_bytes < 1024 * 1024:
                    size_str = f"{size_bytes / 1024:.1f} KB"
                else:
                    size_str = f"{size_bytes / (1024 * 1024):.1f} MB"
                lines.append(f"   Size: {size_str}")

            lines.append(f"   Modified: {file_info['modified']}")
            lines.append("")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for list_files script."""
    parser = argparse.ArgumentParser(
        description='List files in the local documents directory',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Base Directory: {DOCUMENTS_BASE}

Examples:
  # List files in root
  %(prog)s

  # List markdown files
  %(prog)s --pattern "*.md"

  # List all files recursively
  %(prog)s --recursive

  # List files in subfolder
  %(prog)s "projects" --pattern "*.md" --json
        """
    )

    # Optional arguments
    parser.add_argument(
        'directory',
        nargs='?',
        default='.',
        help='Directory to list (relative to documents folder, default: ".")'
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

    except FileNotFoundError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'FileNotFoundError',
                'message': str(e),
                'suggestions': [
                    'Check that the directory exists',
                    'Use create_folder.py to create directories',
                    'Verify the path is correct'
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
                    'Verify permissions',
                    'Ensure documents folder exists'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
