#!/usr/bin/env python3
"""Save URL as Markdown

Fetch web page content and save it as markdown using Jina.ai Reader API.
"""

import argparse
import json
import logging
import os
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import requests
import urllib3

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.favicon_service import FaviconService
    from api.services.jina_service import JinaService
    from api.services.web_save_parser import (
        ParsedPage,
        build_frontmatter,
        extract_favicon_url,
        parse_url_local,
    )
    from api.services.web_save_parser_apple_news import resolve_apple_news_source_url
    from api.services.web_save_tagger import (
        calculate_reading_time,
        compute_word_count,
        extract_tags,
    )
    from api.services.website_title_service import resolve_website_title
    from api.services.websites_service import WebsitesService
except Exception:
    SessionLocal = None
    WebsitesService = None
    FaviconService = None
    resolve_website_title = None
    resolve_apple_news_source_url = None
    JinaService = None


if not logging.getLogger().handlers:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )

logger = logging.getLogger(__name__)


def _clean_metadata_value(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    if cleaned.lower() in {"undefined", "null", "none", "n/a"}:
        return None
    return cleaned


def extract_title(content: str) -> str:
    """Extract title from markdown content.

    Args:
        content: Markdown content string

    Returns:
        Extracted title or None
    """
    # First try to find a # Title or # Header
    title_match = re.search(r"^#\s+(.+)", content, re.MULTILINE)
    if title_match:
        return title_match.group(1).strip()

    # Then try to find a "Title:" line
    title_line_match = re.search(r"^Title:\s*(.+)", content, re.MULTILINE)
    if title_line_match:
        return title_line_match.group(1).strip()

    # If no title found, look for the first non-empty line
    lines = content.split("\n")
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("---") and not stripped.startswith("#"):
            # Limit title length
            return stripped[:100]

    return None


def parse_published_at(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_jina_metadata(content: str) -> tuple[dict[str, str | None], str]:
    metadata: dict[str, str | None] = {
        "title": None,
        "url_source": None,
        "published_time": None,
    }

    title_match = re.search(r"^Title:\s*(.+)$", content, re.MULTILINE)
    if title_match:
        metadata["title"] = _clean_metadata_value(title_match.group(1))

    url_match = re.search(r"^URL Source:\s*(.+)$", content, re.MULTILINE)
    if url_match:
        metadata["url_source"] = _clean_metadata_value(url_match.group(1))

    published_match = re.search(r"^Published Time:\s*(.+)$", content, re.MULTILINE)
    if published_match:
        metadata["published_time"] = _clean_metadata_value(published_match.group(1))

    cleaned = content
    cleaned = re.sub(r"^Title:.*\n?", "", cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r"^URL Source:.*\n?", "", cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r"^Published Time:.*\n?", "", cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r"^Markdown Content:\s*", "", cleaned, flags=re.MULTILINE)
    cleaned = cleaned.lstrip()

    return metadata, cleaned


def get_markdown_content(url: str, api_key: str) -> str:
    """Fetch markdown content from Jina.ai API.

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
            'Add it to Doppler secrets: doppler secrets set JINA_API_KEY "your-key"'
        )

    headers = {"Authorization": f"Bearer {api_key}"}

    ssl_verify = os.environ.get("JINA_SSL_VERIFY", "true").lower()
    verify_setting: Any = ssl_verify not in {"0", "false", "no", "off"}
    ca_bundle = os.environ.get("JINA_CA_BUNDLE")
    if ca_bundle:
        verify_setting = ca_bundle
    if verify_setting is False:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    jina_url = f"https://r.jina.ai/{url}"

    try:
        response = requests.get(
            jina_url, headers=headers, timeout=30, verify=verify_setting
        )
        response.raise_for_status()
        return response.text
    except requests.exceptions.RequestException as e:
        raise requests.exceptions.RequestException(
            f"Failed to fetch content from Jina.ai: {str(e)}"
        ) from e


def save_url_database(url: str, user_id: str) -> dict[str, Any]:
    if SessionLocal is None or WebsitesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    if not url.startswith(("http://", "https://")):
        url = "https://" + url

    target_url = (
        resolve_apple_news_source_url(url)
        if resolve_apple_news_source_url is not None
        else url
    )
    web_save_mode = os.getenv("WEB_SAVE_MODE", "local").lower().strip()
    logger.info(
        "web-save script start url=%s target_url=%s mode=%s",
        url,
        target_url,
        web_save_mode,
    )
    parsed = None
    local_parse_error: str | None = None
    if web_save_mode in {"local", "compare"}:
        try:
            parsed = parse_url_local(target_url)
            logger.info(
                (
                    "web-save script local parse ok url=%s "
                    "target_url=%s title=%s content_len=%s"
                ),
                url,
                target_url,
                parsed.title,
                len(parsed.content),
            )
        except Exception as exc:
            local_parse_error = str(exc)
            logger.exception(
                "web-save script local parse failed target_url=%s error=%s",
                target_url,
                local_parse_error,
            )

    local_parsed = parsed
    if parsed is None or web_save_mode in {"jina", "compare"}:
        logger.info(
            "web-save script using jina url=%s target_url=%s mode=%s",
            url,
            target_url,
            web_save_mode,
        )
        api_key = os.environ.get("JINA_API_KEY", "")
        try:
            content = get_markdown_content(target_url, api_key)
            parsed_metadata, cleaned_content = parse_jina_metadata(content)
            source = parsed_metadata.get("url_source") or target_url
            if JinaService is not None:
                cleaned_content = JinaService.clean_markdown_for_source(
                    cleaned_content, source
                )
            candidate_title = parsed_metadata.get("title") or extract_title(
                cleaned_content
            )
            if resolve_website_title is not None:
                title = (
                    resolve_website_title(candidate_title, url=source)
                    or urlparse(source).netloc
                )
            else:
                title = candidate_title or urlparse(source).netloc
            published_at = parse_published_at(parsed_metadata.get("published_time"))
            word_count = compute_word_count(cleaned_content)
            domain = urlparse(source).netloc
            tags = extract_tags(cleaned_content, domain, title)
            frontmatter = build_frontmatter(
                cleaned_content,
                meta={
                    "source": source,
                    "title": title,
                    "published_date": published_at.isoformat()
                    if published_at
                    else None,
                    "domain": domain,
                    "word_count": word_count,
                    "reading_time": calculate_reading_time(word_count),
                    "tags": tags,
                    "saved_at": datetime.now(UTC).isoformat(),
                },
            )
            parsed = ParsedPage(
                title=title,
                content=frontmatter,
                source=source,
                published_at=published_at,
            )
            if web_save_mode == "compare" and local_parsed is not None:
                logger.info(
                    "Compare parse for %s: jina_len=%s local_len=%s jina_title=%s local_title=%s",
                    target_url,
                    len(cleaned_content),
                    len(local_parsed.content),
                    title,
                    local_parsed.title,
                )
        except Exception as exc:
            if web_save_mode == "compare" and local_parsed is not None:
                logger.info("Compare parse failed for %s: %s", url, str(exc))
                parsed = local_parsed
            else:
                if local_parse_error:
                    raise requests.exceptions.RequestException(
                        (
                            "Local parse failed (%s); "
                            "Jina fallback failed: %s"
                        )
                        % (local_parse_error, str(exc))
                    ) from exc
                raise
    else:
        title = parsed.title
        source = parsed.source
        published_at = parsed.published_at

    if parsed is None:
        raise RuntimeError("Failed to parse URL")

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        website = WebsitesService.upsert_website(
            db,
            user_id,
            url=url,
            title=title,
            content=parsed.content,
            source=source,
            url_full=url,
            saved_at=datetime.now(UTC),
            published_at=published_at,
            pinned=False,
            archived=False,
        )
        favicon_url = parsed.favicon_url
        if favicon_url is None:
            try:
                favicon_url = extract_favicon_url(target_url)
            except Exception:
                favicon_url = None

        if FaviconService is not None and favicon_url:
            try:
                metadata_payload = FaviconService.metadata_payload(
                    favicon_url=favicon_url
                )
                if metadata_payload:
                    try:
                        WebsitesService.update_metadata(
                            db,
                            user_id,
                            website.id,
                            metadata_updates=metadata_payload,
                        )
                    except Exception as exc:
                        logger.warning(
                            "favicon metadata update failed url=%s error=%s",
                            url,
                            exc,
                        )

                shared_key = None
                try:
                    shared_key = FaviconService.existing_storage_key(website.domain)
                except Exception as exc:
                    logger.warning(
                        "favicon shared key check failed url=%s error=%s",
                        url,
                        exc,
                    )

                if shared_key:
                    try:
                        WebsitesService.update_metadata(
                            db,
                            user_id,
                            website.id,
                            metadata_updates={"favicon_r2_key": shared_key},
                        )
                    except Exception as exc:
                        logger.warning(
                            "favicon shared key update failed url=%s error=%s",
                            url,
                            exc,
                        )
                else:
                    try:
                        favicon_key = FaviconService.fetch_and_store_favicon(
                            website.domain,
                            favicon_url,
                        )
                        if favicon_key:
                            WebsitesService.update_metadata(
                                db,
                                user_id,
                                website.id,
                                metadata_updates={"favicon_r2_key": favicon_key},
                            )
                    except Exception as exc:
                        logger.warning(
                            "favicon upload failed url=%s error=%s", url, exc
                        )
            except Exception as exc:
                logger.warning("favicon handling failed url=%s error=%s", url, exc)
        return {
            "id": str(website.id),
            "title": website.title,
            "url": website.url,
            "domain": website.domain,
        }
    finally:
        db.close()


def main():
    """Main entry point for save_url script."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(
        description="Save web page as markdown using Jina.ai Reader API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Save article
  %(prog)s "https://example.com/article"

  # JSON output
  %(prog)s "https://example.com/article" --database --json

Environment Variables:
  JINA_API_KEY: Required. Get from https://jina.ai/
        """,
    )

    # Required argument
    parser.add_argument("url", help="Web page URL to save")

    # Optional arguments
    parser.add_argument(
        "--json", action="store_true", help="Output results in JSON format"
    )
    parser.add_argument(
        "--database", action="store_true", help="Save to database instead of filesystem"
    )
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        # Save the URL
        if not args.database:
            raise ValueError("Database mode required")

        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = save_url_database(url=args.url, user_id=args.user_id)

        # Output results
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))

        sys.exit(0)

    except ValueError as e:
        error_output = {
            "success": False,
            "error": {
                "type": "ValidationError",
                "message": str(e),
                "suggestions": [
                    "Ensure URL is valid and includes http:// or https://",
                    "Set JINA_API_KEY environment variable",
                    "Check Doppler secrets configuration",
                ],
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except requests.exceptions.RequestException as e:
        error_output = {
            "success": False,
            "error": {
                "type": "FetchError",
                "message": str(e),
                "suggestions": [
                    "Check your internet connection",
                    "Verify the URL is accessible",
                    "Set JINA_SSL_VERIFY=false if corporate SSL interception is blocking requests",
                    "Provide a CA bundle via JINA_CA_BUNDLE if needed",
                    "Check if Jina.ai API is operational",
                    "Verify your API key is valid",
                ],
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except OSError as e:
        error_output = {
            "success": False,
            "error": {
                "type": "FileError",
                "message": str(e),
                "suggestions": [
                    "Check that the websites storage path exists and is writable",
                    "Verify disk space is available",
                    "Check file permissions",
                ],
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            "success": False,
            "error": {
                "type": "UnexpectedError",
                "message": f"Unexpected error: {str(e)}",
                "suggestions": [
                    "Check the error message for details",
                    "Verify all requirements are met",
                    "Try again with --json for more details",
                ],
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
