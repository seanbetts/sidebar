#!/usr/bin/env python3
"""Pin or Unpin File in Workspace.

Set pinned state for an ingestion-backed file by path.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if sys.path and sys.path[0] == str(SCRIPT_DIR):
    sys.path.pop(0)
elif str(SCRIPT_DIR) in sys.path:
    sys.path.remove(str(SCRIPT_DIR))

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_ops_ingestion import pin_path  # noqa: E402


def parse_bool(value: str) -> bool:
    """Parse boolean CLI values."""
    return value.lower() in {"true", "1", "yes", "y"}


def pin_entry(user_id: str, path: str, pinned: bool) -> dict[str, Any]:
    """Set pinned state for a file path."""
    result = pin_path(user_id, path, pinned)
    result["action"] = "pinned" if pinned else "unpinned"
    return result


def main() -> None:
    """Main entry point for pin script."""
    parser = argparse.ArgumentParser(
        description="Pin or unpin an ingestion-backed file"
    )

    parser.add_argument(
        "path", help="File path to pin or unpin (relative to workspace)"
    )
    parser.add_argument("--pinned", default="true", help="true or false")
    parser.add_argument(
        "--json", action="store_true", help="Output results in JSON format"
    )
    parser.add_argument(
        "--user-id",
        required=True,
        help="User id for storage access",
    )

    args = parser.parse_args()

    try:
        result = pin_entry(args.user_id, args.path, parse_bool(args.pinned))
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileNotFoundError) as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {"success": False, "error": f"Unexpected error: {str(e)}"}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
