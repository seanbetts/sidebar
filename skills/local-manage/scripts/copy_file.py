#!/usr/bin/env python3
"""Copy File"""
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

def copy_file(source, dest):
    src_path = validate_path(source)
    dest_path = validate_path(dest)
    if not src_path.exists():
        raise FileNotFoundError(f"Source not found: {source}")
    if not src_path.is_file():
        raise ValueError("Can only copy files (not directories)")
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_path, dest_path)
    return {'source': source, 'destination': dest, 'copied': True}

def main():
    parser = argparse.ArgumentParser(description='Copy file')
    parser.add_argument('source', help='Source path')
    parser.add_argument('destination', help='Destination path')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    try:
        result = copy_file(args.source, args.destination)
        print(json.dumps({'success': True, 'data': result}, indent=2) if args.json else f"Copied: {result['source']} → {result['destination']}")
        sys.exit(0)
    except Exception as e:
        print(json.dumps({'success': False, 'error': str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
