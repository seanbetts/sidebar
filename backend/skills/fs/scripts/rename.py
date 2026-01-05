#!/usr/bin/env python3
"""
Rename File or Directory in Workspace

Rename files or directories within workspace (in same directory).
"""

import sys
import json
import argparse
from pathlib import Path
from typing import Dict, Any

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_ops_ingestion import move_path  # noqa: E402


def rename_path(
    user_id: str,
    path: str,
    new_name: str,
    dry_run: bool = False,
) -> Dict[str, Any]:
    """Rename a file or directory (stays in same directory)."""
    if "/" in new_name or "\\" in new_name:
        raise ValueError("new_name must be a simple name, not a path")

    parent = Path(path).parent.as_posix()
    if parent == ".":
        parent = ""
    destination = f"{parent}/{new_name}".strip("/")

    if dry_run:
        return {
            "success": True,
            "dry_run": True,
            "data": {
                "old_name": Path(path).name,
                "new_name": new_name,
                "path": parent,
                "message": f"Would rename '{Path(path).name}' to '{new_name}'",
            },
        }

    result = move_path(user_id, path, destination)
    result["old_name"] = Path(path).name
    result["new_name"] = new_name
    result["message"] = f"Renamed '{Path(path).name}' to '{new_name}'"
    return {"success": True, "data": result}


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Rename file or directory within workspace"
    )
    parser.add_argument("path", help="Path to rename (relative to workspace)")
    parser.add_argument("new_name", help="New name (just the name, not a path)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate but don't actually rename"
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
        result = rename_path(args.user_id, args.path, args.new_name, args.dry_run)

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
