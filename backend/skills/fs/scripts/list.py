#!/usr/bin/env python3
"""
List Files in Workspace

List files in the workspace directory with pattern filtering and recursive option.
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

from api.services.skill_file_ops_ingestion import list_entries


def list_files(
    user_id: str,
    directory: str = ".",
    pattern: str = "*",
    recursive: bool = False,
) -> Dict[str, Any]:
    """List files in a directory."""
    return list_entries(user_id, directory, pattern, recursive)


def main():
    """Main entry point for list script."""
    parser = argparse.ArgumentParser(
        description='List files in the workspace directory',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    # Optional arguments
    parser.add_argument(
        'directory',
        nargs='?',
        default='.',
        help='Directory to list (relative to workspace, default: ".")'
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
    parser.add_argument(
        "--user-id",
        required=True,
        help="User id for storage access",
    )

    args = parser.parse_args()

    try:
        # List files
        result = list_files(
            user_id=args.user_id,
            directory=args.directory,
            pattern=args.pattern,
            recursive=args.recursive,
        )

        # Output results
        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except ValueError as e:
        error_output = {
            'success': False,
            'error': str(e)
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except FileNotFoundError as e:
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
