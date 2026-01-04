#!/usr/bin/env python3
"""
Write File to Workspace

Create or update files in workspace with multiple modes.
"""

import sys
import json
import argparse
import os
from pathlib import Path
from typing import Dict, Any

SCRIPT_DIR = Path(__file__).resolve().parent
if sys.path and sys.path[0] == str(SCRIPT_DIR):
    sys.path.pop(0)
elif str(SCRIPT_DIR) in sys.path:
    sys.path.remove(str(SCRIPT_DIR))

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_ops_ingestion import write_text


def write_file(
    user_id: str,
    filename: str,
    content: str,
    mode: str = "replace",
) -> Dict[str, Any]:
    """Write content to a file."""
    wait_for_ready = os.getenv("TESTING", "").lower() not in {"1", "true", "yes", "on"}
    return write_text(user_id, filename, content, mode=mode, wait_for_ready=wait_for_ready)


def main():
    """Main entry point for write script."""
    parser = argparse.ArgumentParser(
        description='Write file content to workspace'
    )

    parser.add_argument(
        'filename',
        help='File to write (relative to workspace)'
    )
    parser.add_argument(
        '--content',
        required=True,
        help='Content to write to file'
    )
    parser.add_argument(
        '--mode',
        default='replace',
        choices=['create', 'replace', 'append'],
        help='Write mode: create (fail if exists), replace (default), or append'
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
        result = write_file(
            args.user_id,
            args.filename,
            args.content,
            args.mode,
        )

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileExistsError, FileNotFoundError) as e:
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
