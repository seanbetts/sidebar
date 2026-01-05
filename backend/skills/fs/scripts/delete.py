#!/usr/bin/env python3
"""
Delete File/Directory from Workspace

Delete a file or directory from workspace.
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

from api.services.skill_file_ops_ingestion import delete_path  # noqa: E402


def delete_entry(
    user_id: str,
    path: str,
    recursive: bool = False,
) -> Dict[str, Any]:
    """Delete a file or directory."""
    if not recursive and path.endswith("/"):
        raise ValueError("Directory delete requires --recursive")
    result = delete_path(user_id, path)
    deleted = result.get("deleted", [])
    item_type = "directory" if len(deleted) > 1 else "file"
    return {
        "path": path,
        "type": item_type,
        "action": "deleted",
        "deleted": deleted,
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
    parser.add_argument(
        "--user-id",
        required=True,
        help="User id for storage access",
    )

    args = parser.parse_args()

    try:
        result = delete_entry(args.user_id, args.path, args.recursive)

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
