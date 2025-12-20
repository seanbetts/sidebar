#!/usr/bin/env python3
"""Read Local File - Read file content from local documents directory"""
import sys, json, argparse
from pathlib import Path
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

def read_file(filename: str, lines: int = None) -> Dict[str, Any]:
    file_path = validate_path(filename)
    if not file_path.exists():
        raise FileNotFoundError(f"File not found: {filename}")
    if not file_path.is_file():
        raise ValueError(f"Path is not a file: {filename}")

    content = file_path.read_text(encoding='utf-8')

    if lines:
        content_lines = content.splitlines(keepends=True)
        content = ''.join(content_lines[:lines])

    return {
        'path': str(file_path.relative_to(DOCUMENTS_BASE)),
        'content': content,
        'size': file_path.stat().st_size,
        'lines': len(content.splitlines())
    }

def main():
    parser = argparse.ArgumentParser(description='Read file content')
    parser.add_argument('filename', help='File to read')
    parser.add_argument('--lines', type=int, help='Only read first N lines')
    parser.add_argument('--json', action='store_true', help='JSON output')
    args = parser.parse_args()

    try:
        result = read_file(args.filename, args.lines)
        if args.json:
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            print(result['content'], end='')
        sys.exit(0)
    except (ValueError, FileNotFoundError) as e:
        print(json.dumps({'success': False, 'error': {'type': type(e).__name__, 'message': str(e)}}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
