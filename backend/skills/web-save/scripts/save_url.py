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

# Base websites directory (use workspace if available, fallback to local)
WEBSITES_BASE = Path(os.getenv("WORKSPACE_BASE", str(Path.home() / "Agent Smith"))) / "websites"

try:
    from api.db.session import SessionLocal
    from api.services.websites_service import WebsitesService
except Exception:
    SessionLocal = None
    WebsitesService = None


def sanitize_filename(title: str) -> str:
    """
    Convert a string into a safe filename.

    Args:
        title: String to convert to filename

    Returns:
        Sanitized filename string
    """
    # Remove or replace invalid filename characters
    safe_title = re.sub(r'[<>:"/\\|?*]', '', title)
    # Replace spaces with dashes
    safe_title = safe_title.replace(' ', '-')
    # Remove multiple dashes
    safe_title = re.sub(r'-+', '-', safe_title)
    # Remove leading/trailing dashes
    return safe_title.strip('-')


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


def save_url(
    url: str,
    folder: str = None,
    filename: str = None
) -> Dict[str, Any]:
    """
    Fetch URL and save as markdown file.

    Args:
        url: Web page URL to save
        folder: Optional subfolder within Websites/
        filename: Optional custom filename (without .md extension)

    Returns:
        Dictionary with file info and metadata

    Raises:
        ValueError: If URL or API key invalid
        requests.exceptions.RequestException: If fetch fails
        IOError: If file save fails
    """
    # Ensure URL has protocol
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url

    # Get API key from environment
    api_key = os.environ.get('JINA_API_KEY', '')

    # Fetch markdown content
    content = get_markdown_content(url, api_key)

    # Determine save location
    if folder:
        save_path = WEBSITES_BASE / folder
    else:
        save_path = WEBSITES_BASE

    # Create directory if it doesn't exist
    save_path.mkdir(parents=True, exist_ok=True)

    # Determine filename
    if filename:
        # Use provided filename
        safe_filename = sanitize_filename(filename)
    else:
        # Extract title from content
        title = extract_title(content)
        if title:
            safe_filename = sanitize_filename(title)
        else:
            # Use domain name as fallback
            domain = url.split("//")[-1].split("/")[0]
            safe_filename = sanitize_filename(domain)

    # Ensure .md extension
    if not safe_filename.endswith('.md'):
        safe_filename += '.md'

    # Full path for the markdown file
    file_path = save_path / safe_filename

    # Create content with metadata
    today = datetime.now().strftime('%Y-%m-%d')
    full_content = f"""---
source: {url}
date: {today}
---

{content}"""

    # Save file
    try:
        file_path.write_text(full_content, encoding='utf-8')
    except IOError as e:
        raise IOError(f"Failed to save file: {str(e)}") from e

    # Get file info
    file_size = file_path.stat().st_size
    relative_path = file_path.relative_to(WEBSITES_BASE)

    return {
        'path': str(file_path),
        'relative_path': str(relative_path),
        'filename': safe_filename,
        'size': file_size,
        'url': url,
        'date': today,
        'saved': True
    }


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


def format_human_readable(result: Dict[str, Any]) -> str:
    """
    Format result in human-readable format.

    Args:
        result: Result dictionary from save_url

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("WEB PAGE SAVED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    lines.append(f"Source URL: {result['url']}")
    lines.append(f"Saved to: {result['relative_path']}")
    lines.append(f"Full Path: {result['path']}")
    lines.append(f"Size: {result['size']:,} bytes")
    lines.append(f"Date: {result['date']}")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for save_url script."""
    parser = argparse.ArgumentParser(
        description='Save web page as markdown using Jina.ai Reader API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Base Directory: {WEBSITES_BASE}

Examples:
  # Save article
  %(prog)s "https://example.com/article"

  # Save to subfolder
  %(prog)s "https://example.com/article" --folder "Tech Articles"

  # Custom filename
  %(prog)s "https://example.com/article" --filename "my-article"

  # JSON output
  %(prog)s "https://example.com/article" --json

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
        '--folder',
        help='Subfolder within Websites/ to save to'
    )
    parser.add_argument(
        '--filename',
        help='Custom filename (without .md extension)'
    )
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
        if args.database:
            result = save_url_database(url=args.url)
        else:
            result = save_url(
                url=args.url,
                folder=args.folder,
                filename=args.filename
            )

        # Output results
        if args.json:
            output = {
                'success': True,
                'data': result
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(result))

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
