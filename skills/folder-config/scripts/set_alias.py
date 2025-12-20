#!/usr/bin/env python3
"""Set or update a folder alias"""
import sys
import json
import argparse
import yaml
from pathlib import Path

DOCUMENTS_BASE = Path.home() / "Documents" / "Agent Smith" / "Documents"
CONFIG_DIR = Path.home() / ".agent-smith"
CONFIG_FILE = CONFIG_DIR / "folder_config.yaml"

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

def save_config(config):
    """Save configuration to file"""
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=True)

def validate_path(relative_path):
    """Validate that the path exists within DOCUMENTS_BASE"""
    full_path = DOCUMENTS_BASE / relative_path

    if not full_path.exists():
        raise FileNotFoundError(f"Path not found: {relative_path}")

    if not full_path.is_dir():
        raise ValueError(f"Path is not a directory: {relative_path}")

    # Ensure path is within DOCUMENTS_BASE
    try:
        full_path.resolve().relative_to(DOCUMENTS_BASE.resolve())
    except ValueError:
        raise ValueError(f"Path must be within {DOCUMENTS_BASE}")

    return relative_path

def set_alias(alias, path):
    """
    Set or update a folder alias.

    Args:
        alias: Alias name (without @ prefix)
        path: Relative path from DOCUMENTS_BASE

    Returns:
        dict: Result with alias, path, and whether it was new or updated
    """
    # Remove @ prefix if present
    if alias.startswith('@'):
        alias = alias[1:]

    # Validate alias name (alphanumeric, hyphens, underscores only)
    if not alias.replace('-', '').replace('_', '').isalnum():
        raise ValueError(f"Invalid alias name: {alias}. Use only letters, numbers, hyphens, and underscores.")

    # Validate path exists
    validated_path = validate_path(path)

    # Load config and update
    config = load_config()
    is_new = alias not in config['aliases']
    old_path = config['aliases'].get(alias)

    config['aliases'][alias] = validated_path
    save_config(config)

    return {
        'alias': alias,
        'path': validated_path,
        'old_path': old_path,
        'is_new': is_new
    }

def main():
    parser = argparse.ArgumentParser(description='Set or update a folder alias')
    parser.add_argument('alias', help='Alias name (without @ prefix)')
    parser.add_argument('path', help='Relative path from Documents folder')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    args = parser.parse_args()

    try:
        result = set_alias(args.alias, args.path)

        if args.json:
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            action = "Created" if result['is_new'] else "Updated"
            print(f"✅ {action} alias: @{result['alias']} → {result['path']}")
            if not result['is_new'] and result['old_path']:
                print(f"   (was: {result['old_path']})")

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
