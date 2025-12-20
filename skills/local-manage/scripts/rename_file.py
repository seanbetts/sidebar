#!/usr/bin/env python3
"""Rename File"""
import sys, json, argparse
from pathlib import Path

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"

def validate_path(p):
    full = (DOCUMENTS_BASE / p).resolve()
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
