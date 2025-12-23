#!/usr/bin/env python3
"""
Save URL as Markdown

Fetch web page content and save it as markdown using Jina.ai Reader API.
"""

import sys
import json
import argparse
import os
import re
import requests
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any
from urllib.parse import urlparse

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal
    from api.services.websites_service import WebsitesService
except Exception:
    SessionLocal = None
    WebsitesService = None


def extract_title(content: str) -> str:
    """
    Extract title from markdown content.

    Args:
        content: Markdown content string

    Returns:
        Extracted title or None
    """
    # First try to find a # Title or # Header
    title_match = re.search(r'^#\s+(.+)', content, re.MULTILINE)
    if title_match:
        return title_match.group(1).strip()

    # Then try to find a "Title:" line
    title_line_match = re.search(r'^Title:\s*(.+)', content, re.MULTILINE)
    if title_line_match:
        return title_line_match.group(1).strip()

    # If no title found, look for the first non-empty line
    lines = content.split('\n')
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith('---') and not stripped.startswith('#'):
            # Limit title length
            return stripped[:100]

    return None


def get_markdown_content(url: str, api_key: str) -> str:
    """
    Fetch markdown content from Jina.ai API.

    Args:
        url: Web page URL to fetch
        api_key: Jina.ai API key

    Returns:
        Markdown content string

    Raises:
        requests.exceptions.RequestException: If fetch fails
        ValueError: If API key is missing
    """
    if not api_key:
        raise ValueError(
            "JINA_API_KEY environment variable not set. "
            "Add it to Doppler secrets: doppler secrets set JINA_API_KEY \"your-key\""
        )

    headers = {
        "Authorization": f"Bearer {api_key}"
    }

    jina_url = f"https://r.jina.ai/{url}"

    try:
        response = requests.get(jina_url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.text
    except requests.exceptions.RequestException as e:
        raise requests.exceptions.RequestException(
            f"Failed to fetch content from Jina.ai: {str(e)}"
        ) from e


def save_url_database(url: str) -> Dict[str, Any]:
    if SessionLocal is None or WebsitesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url

    api_key = os.environ.get('JINA_API_KEY', '')
    content = get_markdown_content(url, api_key)
    title = extract_title(content) or urlparse(url).netloc

    db = SessionLocal()
    try:
        website = WebsitesService.save_website(
            db,
            url=url,
            title=title,
            content=content,
            source=url,
            saved_at=datetime.now(timezone.utc),
            pinned=False,
            archived=False,
        )
        return {
            "id": str(website.id),
            "title": website.title,
            "url": website.url,
            "domain": website.domain
        }
    finally:
        db.close()


def main():
    """Main entry point for save_url script."""
    parser = argparse.ArgumentParser(
        description='Save web page as markdown using Jina.ai Reader API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Examples:
  # Save article
  %(prog)s "https://example.com/article"

  # JSON output
  %(prog)s "https://example.com/article" --database --json

Environment Variables:
  JINA_API_KEY: Required. Get from https://jina.ai/
        """
    )

    # Required argument
    parser.add_argument(
        'url',
        help='Web page URL to save'
    )

    # Optional arguments
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    parser.add_argument(
        '--database',
        action='store_true',
        help='Save to database instead of filesystem'
    )

    args = parser.parse_args()

    try:
        # Save the URL
        if not args.database:
            raise ValueError("Database mode required")

        result = save_url_database(url=args.url)

        # Output results
        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))

        sys.exit(0)

    except ValueError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'ValidationError',
                'message': str(e),
                'suggestions': [
                    'Ensure URL is valid and includes http:// or https://',
                    'Set JINA_API_KEY environment variable',
                    'Check Doppler secrets configuration'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except requests.exceptions.RequestException as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'FetchError',
                'message': str(e),
                'suggestions': [
                    'Check your internet connection',
                    'Verify the URL is accessible',
                    'Check if Jina.ai API is operational',
                    'Verify your API key is valid'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except IOError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'FileError',
                'message': str(e),
                'suggestions': [
                    f'Check that {WEBSITES_BASE} exists and is writable',
                    'Verify disk space is available',
                    'Check file permissions'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'UnexpectedError',
                'message': f'Unexpected error: {str(e)}',
                'suggestions': [
                    'Check the error message for details',
                    'Verify all requirements are met',
                    'Try again with --json for more details'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
