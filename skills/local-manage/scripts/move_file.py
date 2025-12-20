#!/usr/bin/env python3
"""Move File - Move file to new location"""
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
        raise ValueError(f"Path escapes documents folder")
    return full

def move_file(source, dest):
    src_path = validate_path(source)
    dest_path = validate_path(dest)
    if not src_path.exists():
        raise FileNotFoundError(f"Source not found: {source}")
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src_path), str(dest_path))
    return {'source': source, 'destination': dest, 'moved': True}

def main():
    parser = argparse.ArgumentParser(description='Move file')
    parser.add_argument('source', help='Source path')
    parser.add_argument('destination', help='Destination path')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    try:
        result = move_file(args.source, args.destination)
        print(json.dumps({'success': True, 'data': result}, indent=2) if args.json else f"Moved: {result['source']} → {result['destination']}")
        sys.exit(0)
    except Exception as e:
        print(json.dumps({'success': False, 'error': str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
