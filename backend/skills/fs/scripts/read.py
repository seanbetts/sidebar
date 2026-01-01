#!/usr/bin/env python3
"""
Read File from Workspace

Read file content with optional line range support.
"""

import sys
import json
import argparse
from pathlib import Path
from typing import Dict, Any

SCRIPT_DIR = Path(__file__).resolve().parent
if sys.path and sys.path[0] == str(SCRIPT_DIR):
    sys.path.pop(0)
elif str(SCRIPT_DIR) in sys.path:
    sys.path.remove(str(SCRIPT_DIR))

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_ops_ingestion import read_text


def read_file(
    user_id: str,
    filename: str,
    offset: int = 0,
    lines: int | None = None,
) -> Dict[str, Any]:
    """Read file content with optional line range."""
    content, record = read_text(user_id, filename)
    content_lines = content.splitlines(keepends=True)

    if offset > 0:
        content_lines = content_lines[offset:]
    if lines is not None:
        content_lines = content_lines[:lines]

    filtered_content = ''.join(content_lines)

    return {
        'path': record.path,
        'content': filtered_content,
        'size': record.size_bytes,
        'total_lines': len(content.splitlines()),
        'returned_lines': len(filtered_content.splitlines()),
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
        '--start-line',
        type=int,
        help='Starting line number (1-indexed, overrides --offset)'
    )
    parser.add_argument(
        '--lines',
        type=int,
        help='Number of lines to read (default: all)'
    )
    parser.add_argument(
        '--end-line',
        type=int,
        help='Ending line number (1-indexed)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    parser.add_argument(
        "--user-id",
        required=True,
        help="User id for storage access",
    )

    args = parser.parse_args()

    try:
        offset = args.offset
        lines = args.lines
        if args.start_line is not None:
            offset = max(args.start_line - 1, 0)
        if args.end_line is not None and args.start_line is not None:
            lines = max(args.end_line - args.start_line + 1, 0)
        elif args.end_line is not None:
            lines = max(args.end_line, 0)

        result = read_file(args.user_id, args.filename, offset, lines)

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
