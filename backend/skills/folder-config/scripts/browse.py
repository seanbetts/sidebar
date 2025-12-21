#!/usr/bin/env python3
"""Browse folder structure with tree view"""
import sys
import json
import argparse
from pathlib import Path

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"

def build_tree(path, max_depth=3, current_depth=0, prefix=""):
    """
    Build a tree structure of folders.

    Args:
        path: Path to browse
        max_depth: Maximum depth to display
        current_depth: Current recursion depth
        prefix: Prefix for tree drawing

    Returns:
        list: Lines of tree output
    """
    lines = []

    if not path.exists():
        return [f"{prefix}[Path not found: {path}]"]

    if not path.is_dir():
        return [f"{prefix}[Not a directory: {path}]"]

    # Get all subdirectories, sorted
    try:
        subdirs = sorted([d for d in path.iterdir() if d.is_dir() and not d.name.startswith('.')])
    except PermissionError:
        return [f"{prefix}[Permission denied]"]

    # Display current directory if at root
    if current_depth == 0:
        relative_path = path.relative_to(DOCUMENTS_BASE) if path != DOCUMENTS_BASE else Path(".")
        lines.append(f"{relative_path}/" if str(relative_path) != "." else "Documents/")

    # Display subdirectories
    for i, subdir in enumerate(subdirs):
        is_last = i == len(subdirs) - 1
        connector = "└── " if is_last else "├── "
        lines.append(f"{prefix}{connector}{subdir.name}/")

        # Recurse if not at max depth
        if current_depth < max_depth - 1:
            extension = "    " if is_last else "│   "
            lines.extend(build_tree(subdir, max_depth, current_depth + 1, prefix + extension))

    return lines

def browse_folders(relative_path=".", max_depth=3):
    """
    Browse folder structure starting from relative_path.

    Args:
        relative_path: Starting path relative to DOCUMENTS_BASE
        max_depth: Maximum depth to display

    Returns:
        dict: Tree structure and metadata
    """
    if relative_path == ".":
        start_path = DOCUMENTS_BASE
    else:
        start_path = DOCUMENTS_BASE / relative_path

    if not start_path.exists():
        raise FileNotFoundError(f"Path not found: {relative_path}")

    if not start_path.is_dir():
        raise ValueError(f"Not a directory: {relative_path}")

    tree_lines = build_tree(start_path, max_depth)

    return {
        'base_path': str(DOCUMENTS_BASE),
        'start_path': relative_path,
        'max_depth': max_depth,
        'tree': tree_lines
    }

def main():
    parser = argparse.ArgumentParser(description='Browse folder structure')
    parser.add_argument('--path', default='.', help='Starting path (default: root)')
    parser.add_argument('--depth', type=int, default=3, help='Maximum depth to display (default: 3)')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    args = parser.parse_args()

    try:
        result = browse_folders(args.path, args.depth)

        if args.json:
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            print(f"Folder Structure (max depth: {result['max_depth']})")
            print(f"{'='*60}\n")
            for line in result['tree']:
                print(line)

        sys.exit(0)

    except Exception as e:
        error_msg = {'success': False, 'error': {'type': type(e).__name__, 'message': str(e)}}
        if args.json:
            print(json.dumps(error_msg), file=sys.stderr)
        else:
            print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
