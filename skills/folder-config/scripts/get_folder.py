#!/usr/bin/env python3
"""Resolve folder alias to path"""
import sys
import json
import argparse
import yaml
from pathlib import Path

CONFIG_FILE = Path.home() / ".agent-smith" / "folder_config.yaml"

def load_config():
    """Load folder configuration from file"""
    if not CONFIG_FILE.exists():
        raise FileNotFoundError(
            f"Configuration file not found: {CONFIG_FILE}\n"
            f"Run init_config.py first to create the configuration."
        )

    with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)

    if not config or 'aliases' not in config:
        raise ValueError(f"Invalid configuration file: {CONFIG_FILE}")

    return config

def get_folder(alias):
    """
    Resolve alias to folder path.

    Args:
        alias: Folder alias (with or without @ prefix)

    Returns:
        str: Relative folder path
    """
    # Remove @ prefix if present
    if alias.startswith('@'):
        alias = alias[1:]

    config = load_config()
    aliases = config['aliases']

    if alias not in aliases:
        available_aliases = ', '.join(f"@{a}" for a in sorted(aliases.keys()))
        raise ValueError(
            f"Alias '@{alias}' not found.\n"
            f"Available aliases: {available_aliases}\n"
            f"Use list_folders.py to see all aliases or set_alias.py to create new ones."
        )

    return aliases[alias]

def main():
    parser = argparse.ArgumentParser(description='Resolve folder alias to path')
    parser.add_argument('alias', help='Folder alias (with or without @ prefix)')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    args = parser.parse_args()

    try:
        folder_path = get_folder(args.alias)

        if args.json:
            result = {
                'alias': args.alias.lstrip('@'),
                'path': folder_path,
                'full_path': str(Path.home() / "Documents" / "Agent Smith" / "Documents" / folder_path)
            }
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            print(folder_path)

        sys.exit(0)

    except Exception as e:
        error_msg = {'success': False, 'error': {'type': type(e).__name__, 'message': str(e)}}
        if args.json:
            print(json.dumps(error_msg), file=sys.stderr)
        else:
            print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
