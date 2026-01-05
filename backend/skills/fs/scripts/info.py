#!/usr/bin/env python3
"""
Get File/Directory Info

Get metadata about a file or directory in workspace.
"""

import sys
import json
import argparse
from pathlib import Path
from typing import Dict, Any

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_ops_ingestion import info as fetch_info  # noqa: E402


def get_info(user_id: str, path: str) -> Dict[str, Any]:
    """Get file or directory metadata."""
    info = fetch_info(user_id, path)
    info["name"] = Path(info["path"]).name
    if info["is_file"]:
        info["extension"] = Path(info["path"]).suffix
    info["created"] = info["modified"]
    info["accessed"] = info["modified"]
    info["lines"] = None
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
    parser.add_argument(
        "--user-id",
        required=True,
        help="User id for storage access",
    )

    args = parser.parse_args()

    try:
        result = get_info(args.user_id, args.path)

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
