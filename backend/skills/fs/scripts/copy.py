#!/usr/bin/env python3
"""
Copy File or Directory in Workspace

Copy files or directories within workspace with optional dry-run support.
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

from api.services.skill_file_ops_ingestion import copy_path


def copy_entry(
    user_id: str,
    source: str,
    destination: str,
    dry_run: bool = False,
) -> Dict[str, Any]:
    """Copy a file or directory to a new location."""
    if dry_run:
        return {
            "success": True,
            "dry_run": True,
            "data": {
                "source": source,
                "destination": destination,
                "message": f"Would copy {source} to {destination}",
            },
        }

    result = copy_path(user_id, source, destination)
    result["message"] = f"Copied {source} to {destination}"
    return {"success": True, "data": result}


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Copy file or directory within workspace"
    )
    parser.add_argument("source", help="Source path (relative to workspace)")
    parser.add_argument("destination", help="Destination path (relative to workspace)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate but don't actually copy"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output result as JSON"
    )
    parser.add_argument(
        "--user-id",
        required=True,
        help="User id for storage access",
    )

    args = parser.parse_args()

    try:
        result = copy_entry(args.user_id, args.source, args.destination, args.dry_run)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(f"✓ {result['data']['message']}")

        sys.exit(0)

    except (ValueError, FileNotFoundError, FileExistsError) as e:
        error = {"success": False, "error": str(e)}

        if args.json:
            print(json.dumps(error, indent=2), file=sys.stderr)
        else:
            print(f"✗ Error: {e}", file=sys.stderr)

        sys.exit(1)

    except Exception as e:
        error = {"success": False, "error": f"Unexpected error: {str(e)}"}

        if args.json:
            print(json.dumps(error, indent=2), file=sys.stderr)
        else:
            print(f"✗ Unexpected error: {e}", file=sys.stderr)

        sys.exit(1)


if __name__ == "__main__":
    main()
