#!/usr/bin/env python3
"""Delete File - Permanently delete file or folder"""
import sys, json, argparse, shutil, yaml
from pathlib import Path

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"
CONFIG_FILE = Path.home() / ".agent-smith" / "folder_config.yaml"

def resolve_alias(path: str) -> str:
    if not path.startswith('@'):
        return path
    parts = path[1:].split('/', 1)
    alias = parts[0]
    remainder = parts[1] if len(parts) > 1 else ""
    if not CONFIG_FILE.exists():
        raise ValueError(f"Folder configuration not found")
    with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    if not config or 'aliases' not in config:
        raise ValueError(f"Invalid folder configuration")
    if alias not in config['aliases']:
        raise ValueError(f"Alias '@{alias}' not found")
    folder_path = config['aliases'][alias]
    if remainder:
        return f"{folder_path}/{remainder}"
    return folder_path

def validate_path(p):
    resolved = resolve_alias(p)
    full = (DOCUMENTS_BASE / resolved).resolve()
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
