#!/usr/bin/env python3
"""Delete File - Permanently delete file or folder"""
import sys, json, argparse, shutil
from pathlib import Path

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"

def validate_path(p):
    full = (DOCUMENTS_BASE / p).resolve()
    try:
        full.relative_to(DOCUMENTS_BASE.resolve())
    except ValueError:
        raise ValueError("Path escapes documents folder")
    return full

def delete_file(path, recursive=False):
    file_path = validate_path(path)
    if not file_path.exists():
        raise FileNotFoundError(f"Path not found: {path}")

    if file_path.is_dir():
        if not recursive:
            raise ValueError("Path is a directory. Use --recursive to delete folders")
        shutil.rmtree(file_path)
    else:
        file_path.unlink()

    return {'path': path, 'deleted': True, 'was_directory': file_path.is_dir()}

def main():
    parser = argparse.ArgumentParser(description='Delete file or folder (PERMANENT)')
    parser.add_argument('path', help='Path to delete')
    parser.add_argument('--recursive', action='store_true', help='Delete folders recursively')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    try:
        result = delete_file(args.path, args.recursive)
        print(json.dumps({'success': True, 'data': result}, indent=2) if args.json else f"Deleted: {result['path']}")
        sys.exit(0)
    except Exception as e:
        print(json.dumps({'success': False, 'error': str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
