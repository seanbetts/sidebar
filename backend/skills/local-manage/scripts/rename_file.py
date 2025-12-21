#!/usr/bin/env python3
"""Rename File"""
import sys, json, argparse, yaml
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

def rename_file(old_name, new_name):
    old_path = validate_path(old_name)
    if not old_path.exists():
        raise FileNotFoundError(f"File not found: {old_name}")
    new_path = old_path.parent / new_name
    old_path.rename(new_path)
    return {'old_name': old_name, 'new_name': new_name, 'renamed': True}

def main():
    parser = argparse.ArgumentParser(description='Rename file')
    parser.add_argument('old_name', help='Current filename')
    parser.add_argument('new_name', help='New filename')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    try:
        result = rename_file(args.old_name, args.new_name)
        print(json.dumps({'success': True, 'data': result}, indent=2) if args.json else f"Renamed: {result['old_name']} → {result['new_name']}")
        sys.exit(0)
    except Exception as e:
        print(json.dumps({'success': False, 'error': str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
