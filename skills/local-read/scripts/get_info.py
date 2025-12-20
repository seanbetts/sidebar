#!/usr/bin/env python3
"""Get File/Folder Info - Get metadata for files or folders"""
import sys, json, argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"

def validate_path(relative_path: str) -> Path:
    full_path = (DOCUMENTS_BASE / relative_path).resolve()
    try:
        full_path.relative_to(DOCUMENTS_BASE.resolve())
    except ValueError:
        raise ValueError(f"Path '{relative_path}' escapes documents folder")
    if Path(relative_path).is_absolute():
        raise ValueError("Absolute paths not allowed")
    return full_path

def get_info(path: str) -> Dict[str, Any]:
    file_path = validate_path(path)
    if not file_path.exists():
        raise FileNotFoundError(f"Path not found: {path}")

    stats = file_path.stat()
    return {
        'path': str(file_path.relative_to(DOCUMENTS_BASE)),
        'name': file_path.name,
        'type': 'directory' if file_path.is_dir() else 'file',
        'size': stats.st_size if file_path.is_file() else None,
        'created': datetime.fromtimestamp(stats.st_ctime).isoformat(),
        'modified': datetime.fromtimestamp(stats.st_mtime).isoformat(),
        'is_file': file_path.is_file(),
        'is_directory': file_path.is_dir()
    }

def format_human_readable(result: Dict[str, Any]) -> str:
    lines = ["=" * 80, f"INFO: {result['name']}", "=" * 80, ""]
    lines.append(f"Path: {result['path']}")
    lines.append(f"Type: {result['type']}")
    if result['size']:
        size_mb = result['size'] / (1024 * 1024)
        lines.append(f"Size: {size_mb:.2f} MB" if size_mb >= 1 else f"Size: {result['size'] / 1024:.1f} KB")
    lines.append(f"Created: {result['created']}")
    lines.append(f"Modified: {result['modified']}")
    lines.append("=" * 80)
    return '\n'.join(lines)

def main():
    parser = argparse.ArgumentParser(description='Get file/folder information')
    parser.add_argument('path', help='File or folder path')
    parser.add_argument('--json', action='store_true', help='JSON output')
    args = parser.parse_args()

    try:
        result = get_info(args.path)
        if args.json:
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            print(format_human_readable(result))
        sys.exit(0)
    except (ValueError, FileNotFoundError) as e:
        print(json.dumps({'success': False, 'error': {'type': type(e).__name__, 'message': str(e)}}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
