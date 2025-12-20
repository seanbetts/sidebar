#!/usr/bin/env python3
"""Search Local Files - Search files by name or content"""
import sys, json, argparse, re
from pathlib import Path
from typing import Dict, Any, List

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"

def search_files(name: str = None, content: str = None, extension: str = None) -> Dict[str, Any]:
    if not DOCUMENTS_BASE.exists():
        DOCUMENTS_BASE.mkdir(parents=True, exist_ok=True)

    results = []
    pattern = f"**/*.{extension}" if extension else "**/*"

    for file_path in DOCUMENTS_BASE.rglob("*"):
        if not file_path.is_file():
            continue

        # Extension filter
        if extension and file_path.suffix != f".{extension}":
            continue

        # Name filter
        if name and not file_path.match(name):
            continue

        # Content filter
        matches = None
        if content:
            try:
                file_content = file_path.read_text(encoding='utf-8')
                if content.lower() not in file_content.lower():
                    continue
                # Count matches
                matches = len(re.findall(re.escape(content), file_content, re.IGNORECASE))
            except:
                continue

        relative_path = file_path.relative_to(DOCUMENTS_BASE)
        results.append({
            'path': str(relative_path),
            'size': file_path.stat().st_size,
            'matches': matches
        })

    return {
        'query': {'name': name, 'content': content, 'extension': extension},
        'results': results,
        'count': len(results)
    }

def main():
    parser = argparse.ArgumentParser(description='Search files by name or content')
    parser.add_argument('--name', help='Search filenames (wildcards supported)')
    parser.add_argument('--content', help='Search file content')
    parser.add_argument('--extension', help='Filter by extension (e.g., "md")')
    parser.add_argument('--json', action='store_true', help='JSON output')
    args = parser.parse_args()

    if not any([args.name, args.content]):
        parser.error('Must specify --name or --content')

    try:
        result = search_files(args.name, args.content, args.extension)
        if args.json:
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            print(f"Found {result['count']} file(s):")
            for r in result['results']:
                print(f"  {r['path']}" + (f" ({r['matches']} matches)" if r['matches'] else ""))
        sys.exit(0)
    except Exception as e:
        print(json.dumps({'success': False, 'error': str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
