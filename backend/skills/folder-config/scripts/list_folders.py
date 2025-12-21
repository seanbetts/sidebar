#!/usr/bin/env python3
"""List all configured folder aliases"""
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

def list_folders():
    """List all configured folder aliases"""
    config = load_config()
    return {
        'base_path': config['base_path'],
        'aliases': config['aliases'],
        'count': len(config['aliases'])
    }

def main():
    parser = argparse.ArgumentParser(description='List all folder aliases')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    args = parser.parse_args()

    try:
        result = list_folders()

        if args.json:
            print(json.dumps({'success': True, 'data': result}, indent=2))
        else:
            print(f"Folder Configuration")
            print(f"{'='*60}")
            print(f"Base path: {result['base_path']}")
            print(f"Total aliases: {result['count']}\n")
            print(f"{'Alias':<20} {'Path'}")
            print(f"{'-'*20} {'-'*40}")
            for alias, path in sorted(result['aliases'].items()):
                print(f"@{alias:<19} {path}")

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
