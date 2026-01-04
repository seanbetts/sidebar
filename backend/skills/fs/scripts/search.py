#!/usr/bin/env python3
"""
Search Files in Workspace

Search for files by name pattern or content within workspace.
"""

import sys
import json
import argparse
import re
from pathlib import Path
from typing import Dict, Any, List

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.skill_file_ops import search_entries


def search_files(
    user_id: str,
    directory: str = ".",
    name_pattern: str = None,
    content_pattern: str = None,
    case_sensitive: bool = False,
    max_results: int = 100,
) -> Dict[str, Any]:
    """
    Search for files by name or content.

    Args:
        directory: Directory to search in (relative to workspace)
        name_pattern: Pattern to match filenames (supports wildcards * and ?)
        content_pattern: Pattern to search for in file contents (regex)
        case_sensitive: Whether search should be case-sensitive
        max_results: Maximum number of results to return

    Returns:
        Dictionary with search results

    Raises:
        ValueError: If paths are invalid or no search criteria provided
    """
    if not name_pattern and not content_pattern:
        raise ValueError("Must provide either name_pattern or content_pattern")

    results = []

    # Compile content regex if provided
    content_regex = None
    if content_pattern:
        flags = 0 if case_sensitive else re.IGNORECASE
        try:
            content_regex = re.compile(content_pattern, flags)
        except re.error as e:
            raise ValueError(f"Invalid regex pattern: {e}")

    # Convert glob pattern to regex for name matching
    name_regex = None
    if name_pattern:
        # Convert shell-style wildcards to regex
        pattern_str = name_pattern.replace(".", r"\.")
        pattern_str = pattern_str.replace("*", ".*")
        pattern_str = pattern_str.replace("?", ".")
        pattern_str = f"^{pattern_str}$"
        flags = 0 if case_sensitive else re.IGNORECASE
        name_regex = re.compile(pattern_str, flags)

    results = search_entries(
        user_id,
        directory,
        name_pattern=name_regex,
        content_pattern=content_regex,
        max_results=max_results,
    )

    return {
        "success": True,
        "data": {
            "directory": directory,
            "name_pattern": name_pattern,
            "content_pattern": content_pattern,
            "case_sensitive": case_sensitive,
            "results": results,
            "count": len(results),
            "truncated": len(results) >= max_results
        }
    }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Search for files by name or content"
    )
    parser.add_argument(
        "--directory",
        default=".",
        help="Directory to search in (default: workspace root)"
    )
    parser.add_argument(
        "--name",
        help="Filename pattern (supports * and ? wildcards)"
    )
    parser.add_argument(
        "--content",
        help="Content pattern to search for (regex)"
    )
    parser.add_argument(
        "--case-sensitive",
        action="store_true",
        help="Make search case-sensitive"
    )
    parser.add_argument(
        "--max-results",
        type=int,
        default=100,
        help="Maximum number of results (default: 100)"
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
        result = search_files(
            user_id=args.user_id,
            directory=args.directory,
            name_pattern=args.name,
            content_pattern=args.content,
            case_sensitive=args.case_sensitive,
            max_results=args.max_results,
        )

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            data = result['data']
            print(f"Found {data['count']} results")
            if data['truncated']:
                print(f"(truncated to {args.max_results} results)")
            print()

            for item in data['results']:
                if item['match_type'] == 'name':
                    print(f"  {item['path']}")
                else:
                    print(f"  {item['path']} ({item['match_count']} matches)")
                    for match in item.get('matches', []):
                        print(f"    Line {match['line']}: {match['content']}")

        sys.exit(0)

    except (ValueError, FileNotFoundError) as e:
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
