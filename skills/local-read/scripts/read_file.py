#!/usr/bin/env python3
"""Read Local File - Read file content from local documents directory"""
import sys, json, argparse, yaml
from pathlib import Path
from typing import Dict, Any

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"
CONFIG_FILE = Path.home() / ".agent-smith" / "folder_config.yaml"

def resolve_alias(path: str) -> str:
    """Resolve @alias in path to actual folder path."""
    if not path.startswith('@'):
        return path
    parts = path[1:].split('/', 1)
    alias = parts[0]
    remainder = parts[1] if len(parts) > 1 else ""
    if not CONFIG_FILE.exists():
        raise ValueError(f"Folder configuration not found. Run: python /skills/folder-config/scripts/init_config.py")
    with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    if not config or 'aliases' not in config:
        raise ValueError(f"Invalid folder configuration: {CONFIG_FILE}")
    if alias not in config['aliases']:
        available = ', '.join(f"@{a}" for a in sorted(config['aliases'].keys()))
        raise ValueError(f"Alias '@{alias}' not found. Available aliases: {available}")
    folder_path = config['aliases'][alias]
    if remainder:
        return f"{folder_path}/{remainder}"
    return folder_path

def validate_path(relative_path: str) -> Path:
    resolved_path = resolve_alias(relative_path)
    full_path = (DOCUMENTS_BASE / resolved_path).resolve()
    try:
        full_path.relative_to(DOCUMENTS_BASE.resolve())
    except ValueError:
        raise ValueError(f"Path '{relative_path}' resolves outside documents folder")
    if Path(resolved_path).is_absolute():
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
