#!/usr/bin/env python3
"""Initialize folder configuration by scanning existing structure"""
import sys
import json
import argparse
import yaml
from pathlib import Path
import re

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"
CONFIG_DIR = Path.home() / ".agent-smith"
CONFIG_FILE = CONFIG_DIR / "folder_config.yaml"

def slugify(text):
    """Convert folder name to alias (lowercase, replace spaces/special chars with hyphens)"""
    text = text.lower()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[-\s]+', '-', text)
    return text.strip('-')

def scan_folders(base_path, max_depth=2):
    """
    Scan folder structure and generate alias suggestions.

    Args:
        base_path: Base directory to scan
        max_depth: Maximum depth to scan (default: 2 levels)

    Returns:
        dict: Mapping of alias -> relative path
    """
    aliases = {}

    if not base_path.exists():
        raise FileNotFoundError(f"Documents folder not found: {base_path}")

    # Scan folders up to max_depth
    for item in base_path.rglob("*"):
        if not item.is_dir():
            continue

        # Skip hidden folders
        if any(part.startswith('.') for part in item.parts):
            continue

        relative_path = item.relative_to(base_path)
        depth = len(relative_path.parts)

        if depth > max_depth:
            continue

        # Generate alias from folder name
        folder_name = item.name
        alias = slugify(folder_name)

        # Avoid conflicts: if alias exists, use full path slug
        if alias in aliases and aliases[alias] != str(relative_path):
            # For nested folders, create compound alias
            alias = slugify(str(relative_path).replace('/', '-'))

        aliases[alias] = str(relative_path)

    # Also add top-level aliases
    for item in base_path.iterdir():
        if item.is_dir() and not item.name.startswith('.'):
            alias = slugify(item.name)
            relative_path = item.relative_to(base_path)
            aliases[alias] = str(relative_path)

    return aliases

def create_config(aliases, base_path=DOCUMENTS_BASE):
    """Create configuration file with discovered aliases"""
    config = {
        'base_path': str(base_path),
        'aliases': dict(sorted(aliases.items()))
    }

    # Create config directory if it doesn't exist
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    # Write config file
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=True)

    return config

def main():
    parser = argparse.ArgumentParser(description='Initialize folder configuration')
    parser.add_argument('--max-depth', type=int, default=2, help='Maximum folder depth to scan')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    args = parser.parse_args()

    try:
        # Check if config already exists
        if CONFIG_FILE.exists():
            response = input(f"Config file already exists at {CONFIG_FILE}. Overwrite? (y/N): ")
            if response.lower() != 'y':
                print("Aborted.", file=sys.stderr)
                sys.exit(0)

        # Scan folders and create config
        aliases = scan_folders(DOCUMENTS_BASE, max_depth=args.max_depth)
        config = create_config(aliases, DOCUMENTS_BASE)

        result = {
            'config_file': str(CONFIG_FILE),
            'base_path': str(DOCUMENTS_BASE),
            'aliases_count': len(aliases),
            'aliases': aliases
        }

        if args.json:
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            print(f"✅ Configuration initialized successfully!")
            print(f"Config file: {CONFIG_FILE}")
            print(f"Base path: {DOCUMENTS_BASE}")
            print(f"Discovered {len(aliases)} folder aliases:\n")
            for alias, path in sorted(aliases.items()):
                print(f"  @{alias:20s} → {path}")

        sys.exit(0)

    except Exception as e:
        error_msg = {'success': False, 'error': {'type': type(e).__name__, 'message': str(e)}}
        if args.json:
            print(json.dumps(error_msg), file=sys.stderr)
        else:
            print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
