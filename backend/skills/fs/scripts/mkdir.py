#!/usr/bin/env python3
"""
Create Directory in Workspace

Create a new directory in workspace.
"""

import sys
import json
import argparse
from pathlib import Path
from typing import Dict, Any

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_ops import create_folder


def create_directory(
    user_id: str,
    path: str,
    parents: bool = True,
    exist_ok: bool = False,
) -> Dict[str, Any]:
    """Create a directory entry."""
    if not parents:
        raise ValueError("Non-recursive directory creation is not supported in R2")
    result = create_folder(user_id, path)
    if result["action"] == "exists" and not exist_ok:
        raise FileExistsError(f"Directory already exists: {path}")
    return result


def main():
    """Main entry point for mkdir script."""
    parser = argparse.ArgumentParser(
        description='Create directory in workspace'
    )

    parser.add_argument(
        'path',
        help='Directory to create (relative to workspace)'
    )
    parser.add_argument(
        '--no-parents',
        action='store_true',
        help='Do not create parent directories'
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
        result = create_directory(
            args.user_id,
            args.path,
            parents=not args.no_parents,
            exist_ok=True,
        )

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileExistsError) as e:
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
