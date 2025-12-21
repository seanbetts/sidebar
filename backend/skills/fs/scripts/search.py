#!/usr/bin/env python3
"""
Search Files in Workspace

Search for files by name pattern or content within workspace.
"""

import sys
import json
import os
import argparse
import re
from pathlib import Path
from typing import Dict, Any, List

# Base workspace directory
WORKSPACE_BASE = Path(os.getenv("WORKSPACE_BASE", "/workspace"))


def validate_path(relative_path: str) -> Path:
    """
    Validate that the path is safe and within workspace folder.

    Args:
        relative_path: Relative path from workspace base

    Returns:
        Absolute Path object

    Raises:
        ValueError: If path is invalid or escapes workspace folder
    """
    # Reject path traversal attempts
    if ".." in relative_path:
        raise ValueError(f"Path traversal not allowed: {relative_path}")

    # Convert to Path and resolve
    full_path = (WORKSPACE_BASE / relative_path).resolve()

    # Check that resolved path is within workspace base
    try:
        full_path.relative_to(WORKSPACE_BASE.resolve())
    except ValueError:
        raise ValueError(
            f"Path '{relative_path}' resolves to a location outside workspace"
        )

    # Reject absolute paths in the original input
    if Path(relative_path).is_absolute():
        raise ValueError("Absolute paths not allowed")

    return full_path


def search_files(
    directory: str = ".",
    name_pattern: str = None,
    content_pattern: str = None,
    case_sensitive: bool = False,
    max_results: int = 100
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

    search_dir = validate_path(directory)

    if not search_dir.exists():
        raise FileNotFoundError(f"Directory not found: {directory}")

    if not search_dir.is_dir():
        raise ValueError(f"Path is not a directory: {directory}")

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

    # Search through files
    for file_path in search_dir.rglob('*'):
        if not file_path.is_file():
            continue

        # Check if we've hit max results
        if len(results) >= max_results:
            break

        # Get relative path for display
        relative_path = str(file_path.relative_to(WORKSPACE_BASE))

        # Check name pattern
        if name_regex and not name_regex.match(file_path.name):
            continue

        # If only searching by name, add and continue
        if not content_regex:
            results.append({
                "path": relative_path,
                "name": file_path.name,
                "size": file_path.stat().st_size,
                "match_type": "name"
            })
            continue

        # Search file content
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                matches = list(content_regex.finditer(content))

                if matches:
                    # Get line numbers for matches
                    lines = content.split('\n')
                    match_lines = []

                    for match in matches[:5]:  # Limit to first 5 matches per file
                        # Find which line the match is on
                        line_num = content[:match.start()].count('\n') + 1
                        # Get the line content
                        if line_num <= len(lines):
                            line_content = lines[line_num - 1].strip()
                            match_lines.append({
                                "line": line_num,
                                "content": line_content[:100]  # Limit line length
                            })

                    results.append({
                        "path": relative_path,
                        "name": file_path.name,
                        "size": file_path.stat().st_size,
                        "match_type": "content",
                        "match_count": len(matches),
                        "matches": match_lines
                    })

        except (UnicodeDecodeError, PermissionError):
            # Skip binary files or files we can't read
            continue

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

    args = parser.parse_args()

    try:
        result = search_files(
            directory=args.directory,
            name_pattern=args.name,
            content_pattern=args.content,
            case_sensitive=args.case_sensitive,
            max_results=args.max_results
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
