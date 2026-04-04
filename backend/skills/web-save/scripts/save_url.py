#!/usr/bin/env python3
"""Save URL as Markdown.

Fetch web page content and save it as markdown using Jina.ai Reader API.
"""

import argparse
import json
import logging
import os
import re
import sys
import time
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
    from api.services.script_sentry import (
        capture_script_exception,
        initialize_script_sentry,
    )
    from api.services.url_normalization_service import (
        is_youtube_host,
        normalize_youtube_url,
    )
    from api.services.web_save_antibot import AntibotDetection, detect_antibot_html
    from api.services.web_save_error_service import classify_web_save_failure
    from api.services.web_save_parser import (
        LocalParseFallbackError,
        ParsedPage,
        build_frontmatter,
        extract_favicon_url,
        parse_url_local,
    )
    from api.services.web_save_parser_apple_news import resolve_apple_news_source_url
    from api.services.web_save_parser_wsj import apply_wsj_content_guards
    from api.services.web_save_parser_youtube import fetch_youtube_duration_seconds
    from api.services.web_save_tagger import (
        calculate_reading_time,
        compute_word_count,
        extract_tags,
    )
    from api.services.website_reading_time import (
        normalize_reading_time,
        reading_time_from_duration_seconds,
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
    apply_wsj_content_guards = None
    is_youtube_host = None
    normalize_youtube_url = None
    fetch_youtube_duration_seconds = None
    normalize_reading_time = None
    reading_time_from_duration_seconds = None

    def _noop_initialize_script_sentry(script_name: str) -> bool:
        return False

    def _noop_capture_script_exception(
        exc: BaseException, *, extras: dict[str, Any] | None = None
    ) -> None:
        return None

    initialize_script_sentry = _noop_initialize_script_sentry
    capture_script_exception = _noop_capture_script_exception

    def classify_web_save_failure(
        *,
        upstream_error_type: str | None,
        upstream_message: str | None,
        url: str | None = None,
        target_url: str | None = None,
        mode: str | None = None,
        local_parse_error: str | None = None,
    ) -> dict[str, Any]:
        fallback_message = str(upstream_message or "Unable to save website.")
        return {
            "code": "WEB_SAVE_UNEXPECTED_ERROR",
            "message": fallback_message,
            "details": {
                "upstream_error_type": upstream_error_type or "",
                "upstream_error": fallback_message,
                "url": url,
                "target_url": target_url,
                "mode": mode,
                "local_parse_error": local_parse_error,
            },
            "suggestions": [
                "Retry once to confirm reproducibility.",
                "Include URL and error message in the bug report.",
            ],
        }

    class LocalParseFallbackError(Exception):
        """Fallback placeholder for missing parser dependencies."""

    class AntibotDetection:
        """Placeholder detection payload."""

        def __init__(self, challenge_kind: str, reason: str):
            self.challenge_kind = challenge_kind
            self.reason = reason

    def detect_antibot_html(_html: str | None):
        return None


if not logging.getLogger().handlers:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )

logger = logging.getLogger(__name__)


_JINA_NOISE_MARKERS = (
    "privacy center",
    "cookie policy",
    "manage consent preferences",
    "most popular",
    "newsletter",
    "sign up for",
    "subscribe",
    "navigation drawer",
    "advertiser content",
)
_JINA_TRUNCATION_MARKERS = (
    "continue reading your article with",
    "subscription required",
    "subscribe now",
    "this copy is for your personal, non-commercial use only",
    "sign in to continue reading",
    "article appears truncated",
)
_REUTERS_SHELL_MARKERS = (
    "purchase licensing rights",
    "read next",
    "about reuters",
    "lseg products",
    "information you can trust",
    "follow us",
    "site index",
)
_REUTERS_BIO_MARKERS = (
    "thomson reuters",
    "reports on ",
    "correspondent at reuters",
)
_FASTCOMPANY_SHELL_MARKERS = (
    "featured video",
    "more videos",
    "explore topics",
    "fast company & inc",
    "search by queryly",
    "newsguard",
    "modern ceo",
)
_FASTCOMPANY_SKIP_LINE_MARKERS = (
    "share",
    "facebook linkedin bluesky x link",
    "add on google",
    "listen to this article",
    "0:00 / 0:00",
    "advertisement",
    "login",
    "subscribe",
)
_FASTCOMPANY_PREVIEW_CUTOFF = "expand to continue reading"


class WebSaveScriptError(Exception):
    """Raised when web-save has a classified failure payload."""

    def __init__(self, error_type: str, payload: dict[str, Any]):
        super().__init__(payload.get("message", "Unable to save website."))
        self.error_type = error_type
        self.payload = payload

    def as_error(self) -> dict[str, Any]:
        return {
            "type": self.error_type,
            "code": self.payload.get("code"),
            "message": self.payload.get("message"),
            "details": self.payload.get("details", {}),
            "suggestions": self.payload.get("suggestions", []),
        }


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
    if JinaService is not None:
        metadata, cleaned = JinaService.parse_metadata(content)
        return {
            "title": metadata.get("title"),
            "url_source": metadata.get("url_source"),
            "published_time": metadata.get("published_time"),
            "reading_time": metadata.get("reading_time"),
        }, cleaned

    metadata: dict[str, str | None] = {
        "title": None,
        "url_source": None,
        "published_time": None,
        "reading_time": None,
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
    reading_time_match = re.search(r"^Reading Time:\s*(.+)$", content, re.MULTILINE)
    if reading_time_match:
        metadata["reading_time"] = _clean_metadata_value(reading_time_match.group(1))

    cleaned = content
    cleaned = re.sub(r"^Title:.*\n?", "", cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r"^URL Source:.*\n?", "", cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r"^Published Time:.*\n?", "", cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r"^Reading Time:.*\n?", "", cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r"^Markdown Content:\s*", "", cleaned, flags=re.MULTILINE)
    cleaned = cleaned.lstrip()

    return metadata, cleaned


def _is_youtube_url(value: str) -> bool:
    try:
        host = urlparse(value).netloc
    except ValueError:
        return False
    if not host:
        return False
    if is_youtube_host is not None:
        return is_youtube_host(host)
    normalized = host.lower().strip(".")
    return (
        normalized == "youtube.com"
        or normalized.endswith(".youtube.com")
        or normalized == "youtu.be"
        or normalized.endswith(".youtu.be")
    )


def _resolve_jina_reading_time(
    *,
    metadata: dict[str, str | None],
    source: str,
    fallback_url: str,
    word_count: int,
) -> str:
    metadata_reading_time = (metadata.get("reading_time") or "").strip()
    if metadata_reading_time:
        if normalize_reading_time is not None:
            normalized = normalize_reading_time(metadata_reading_time)
            if normalized:
                return normalized
        return metadata_reading_time

    duration_url = source if _is_youtube_url(source) else fallback_url
    if (
        duration_url
        and _is_youtube_url(duration_url)
        and fetch_youtube_duration_seconds is not None
        and reading_time_from_duration_seconds is not None
    ):
        youtube_seconds = fetch_youtube_duration_seconds(duration_url)
        youtube_reading_time = reading_time_from_duration_seconds(youtube_seconds)
        if youtube_reading_time:
            return youtube_reading_time

    return calculate_reading_time(word_count)


def _build_direct_youtube_page(url: str) -> ParsedPage | None:
    """Return a minimal embed-backed page for direct YouTube URLs."""
    if not _is_youtube_url(url):
        return None

    canonical_url = url
    if normalize_youtube_url is not None:
        try:
            canonical_url = normalize_youtube_url(url)
        except ValueError:
            canonical_url = url

    title = (
        resolve_website_title(None, url=canonical_url)
        if resolve_website_title is not None
        else None
    )
    if not title:
        title = "YouTube"

    reading_time = None
    if (
        fetch_youtube_duration_seconds is not None
        and reading_time_from_duration_seconds is not None
    ):
        seconds = fetch_youtube_duration_seconds(canonical_url)
        reading_time = reading_time_from_duration_seconds(seconds)

    markdown = f"[YouTube]({canonical_url})"
    domain = urlparse(canonical_url).netloc
    tags = extract_tags(markdown, domain, title)
    content = build_frontmatter(
        markdown,
        meta={
            "source": canonical_url,
            "title": title,
            "domain": domain,
            "word_count": 0,
            "reading_time": reading_time,
            "tags": tags,
            "saved_at": datetime.now(UTC).isoformat(),
        },
    )
    return ParsedPage(
        title=title,
        content=content,
        source=canonical_url,
        published_at=None,
    )


def _count_noise_markers(content: str) -> int:
    lowered = content.lower()
    return sum(lowered.count(marker) for marker in _JINA_NOISE_MARKERS)


def _count_truncation_markers(content: str) -> int:
    lowered = content.lower()
    return sum(lowered.count(marker) for marker in _JINA_TRUNCATION_MARKERS)


def _summarize_markdown(content: str) -> dict[str, int]:
    word_count = compute_word_count(content)
    links = len(re.findall(r"(?<!!)\[[^\]]+]\([^)]+\)", content))
    return {
        "chars": len(content),
        "lines": content.count("\n") + (1 if content else 0),
        "words": word_count,
        "links": links,
        "images": len(re.findall(r"!\[[^\]]*]\([^)]+\)", content)),
        "noise_hits": _count_noise_markers(content),
        "truncation_hits": _count_truncation_markers(content),
        "link_density_pct": int((links / max(word_count, 1)) * 100),
    }


def _count_reuters_prose_blocks(content: str) -> int:
    blocks = [block.strip() for block in re.split(r"\n\s*\n", content) if block.strip()]
    prose_blocks = 0
    for block in blocks:
        normalized = " ".join(block.split())
        lowered = normalized.lower()
        if any(marker in lowered for marker in _REUTERS_SHELL_MARKERS):
            continue
        if any(marker in lowered for marker in _REUTERS_BIO_MARKERS):
            continue
        if normalized.startswith(("#", "*", "-", "![", "[")):
            continue
        if normalized.count("](") >= 2:
            continue
        word_count = len(normalized.split())
        if word_count < 12:
            continue
        prose_blocks += 1
    return prose_blocks


def _is_low_quality_reuters_fallback(
    *,
    source: str,
    cleaned_content: str,
    summary: dict[str, int],
) -> bool:
    host = urlparse(source).netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    if host != "reuters.com":
        return False

    lowered = cleaned_content.lower()
    shell_hits = sum(lowered.count(marker) for marker in _REUTERS_SHELL_MARKERS)
    prose_blocks = _count_reuters_prose_blocks(cleaned_content)
    return shell_hits >= 3 and prose_blocks < 3 and summary["link_density_pct"] >= 3


def _normalize_host(value: str) -> str:
    host = urlparse(value).netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    return host


def _normalize_fastcompany_byline(line: str) -> str:
    return re.sub(r"^BY\[", "By [", line, count=1)


def _extract_fastcompany_preview_markdown(content: str, *, source: str) -> str | None:
    if _normalize_host(source) != "fastcompany.com":
        return None

    lines = [line.rstrip() for line in content.splitlines()]
    if not lines:
        return None

    date_index = next(
        (
            idx
            for idx, line in enumerate(lines)
            if re.match(r"^\d{2}-\d{2}-\d{4}", line.strip())
        ),
        None,
    )
    if date_index is None:
        return None

    cutoff_index = next(
        (
            idx
            for idx, line in enumerate(lines[date_index:], start=date_index)
            if _FASTCOMPANY_PREVIEW_CUTOFF in line.lower()
        ),
        len(lines),
    )

    preview_lines = lines[date_index:cutoff_index]
    cleaned_lines: list[str] = []
    paragraph_started = False

    for raw_line in preview_lines:
        line = raw_line.strip()
        if not line:
            if cleaned_lines and cleaned_lines[-1]:
                cleaned_lines.append("")
            continue

        lowered = line.lower()
        if any(marker == lowered for marker in _FASTCOMPANY_SKIP_LINE_MARKERS):
            continue
        if any(marker in lowered for marker in _FASTCOMPANY_SHELL_MARKERS):
            continue
        if line.startswith("![Image 5:"):
            continue
        if line.startswith("03-") and "](" in line:
            continue
        if line.startswith("BY["):
            cleaned_lines.append(_normalize_fastcompany_byline(line))
            continue
        if (
            line.startswith("![Image 4:")
            or line.startswith("**")
            or line.startswith("#")
        ):
            cleaned_lines.append(line)
            continue
        if line.startswith("[") and "](" in line and not line.startswith("[#"):
            continue
        if re.match(r"^\d+:\d+\s*/\s*\d+:\d+$", line):
            continue

        if len(line.split()) >= 12:
            paragraph_started = True
        if paragraph_started:
            cleaned_lines.append(line)

    preview = "\n".join(cleaned_lines).strip()
    if not preview:
        return None
    preview = re.sub(r"\n{3,}", "\n\n", preview).strip()
    if cutoff_index < len(lines):
        preview += "\n\nWarning: This article appears truncated."
    return preview


def _count_fastcompany_prose_blocks(content: str) -> int:
    blocks = [block.strip() for block in re.split(r"\n\s*\n", content) if block.strip()]
    prose_blocks = 0
    for block in blocks:
        lowered = block.lower()
        if any(marker in lowered for marker in _FASTCOMPANY_SHELL_MARKERS):
            continue
        if block.startswith(("#", "*", "-", "![", "[")):
            continue
        if len(block.split()) < 12:
            continue
        prose_blocks += 1
    return prose_blocks


def _is_low_quality_fastcompany_fallback(
    *,
    source: str,
    cleaned_content: str,
    summary: dict[str, int],
) -> bool:
    if _normalize_host(source) != "fastcompany.com":
        return False

    lowered = cleaned_content.lower()
    shell_hits = sum(lowered.count(marker) for marker in _FASTCOMPANY_SHELL_MARKERS)
    prose_blocks = _count_fastcompany_prose_blocks(cleaned_content)
    return shell_hits >= 2 and prose_blocks < 3 and summary["link_density_pct"] >= 3


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

    initialize_script_sentry("web-save.save_url")

    if not url.startswith(("http://", "https://")):
        url = "https://" + url

    target_url = (
        resolve_apple_news_source_url(url)
        if resolve_apple_news_source_url is not None
        else url
    )
    script_started_at = time.monotonic()
    web_save_mode = os.getenv("WEB_SAVE_MODE", "local").lower().strip()
    logger.info(
        "web-save script start url=%s target_url=%s mode=%s",
        url,
        target_url,
        web_save_mode,
    )
    direct_youtube_page = _build_direct_youtube_page(target_url)
    if direct_youtube_page is not None:
        parsed = direct_youtube_page
        title = parsed.title
        source = parsed.source
        published_at = parsed.published_at
    else:
        parsed = None
        title = None
        source = None
        published_at = None
    local_parse_error: str | None = None
    local_parse_error_type: str | None = None
    local_antibot_detection: AntibotDetection | None = None
    local_antibot_stage: str | None = None
    local_antibot_rule_id: str | None = None
    if parsed is None and web_save_mode in {"local", "compare"}:
        local_parse_started_at = time.monotonic()
        try:
            parsed = parse_url_local(target_url)
            logger.info(
                (
                    "web-save script local parse ok url=%s "
                    "target_url=%s title=%s content_len=%s parse_elapsed_ms=%s"
                ),
                url,
                target_url,
                parsed.title,
                len(parsed.content),
                int((time.monotonic() - local_parse_started_at) * 1000),
            )
        except LocalParseFallbackError as exc:
            local_antibot_detection = exc.antibot_detection
            local_antibot_stage = exc.stage
            local_antibot_rule_id = exc.rule_id
            local_parse_error = str(exc)
            local_parse_error_type = type(exc).__name__
            logger.info(
                (
                    "web-save local parse fallback requested target_url=%s "
                    "fallback=%s rule=%s stage=%s kind=%s reason=%s"
                ),
                target_url,
                exc.fallback,
                exc.rule_id,
                exc.stage,
                local_antibot_detection.challenge_kind
                if local_antibot_detection
                else None,
                local_antibot_detection.reason if local_antibot_detection else None,
            )
        except Exception as exc:
            local_parse_error = str(exc)
            local_parse_error_type = type(exc).__name__
            capture_script_exception(
                exc,
                extras={
                    "target_url": target_url,
                    "mode": web_save_mode,
                },
            )
            logger.exception(
                "web-save script local parse failed target_url=%s error=%s",
                target_url,
                local_parse_error,
            )

    local_parsed = parsed
    if parsed is None or (
        direct_youtube_page is None and web_save_mode in {"jina", "compare"}
    ):
        fallback_started_at = time.monotonic()
        fallback_reason = (
            "forced_mode"
            if web_save_mode == "jina"
            else "antibot_local_parse"
            if local_antibot_detection
            else "local_parse_error"
            if local_parse_error
            else "compare_mode"
        )
        logger.info(
            (
                "web-save fallback start url=%s target_url=%s provider=jina "
                "reason=%s local_error_type=%s antibot_kind=%s antibot_reason=%s"
            ),
            url,
            target_url,
            fallback_reason,
            local_parse_error_type,
            local_antibot_detection.challenge_kind
            if local_antibot_detection
            else None,
            local_antibot_detection.reason if local_antibot_detection else None,
        )
        logger.info(
            "web-save script using jina url=%s target_url=%s mode=%s",
            url,
            target_url,
            web_save_mode,
        )
        api_key = os.environ.get("JINA_API_KEY", "")
        try:
            content = get_markdown_content(target_url, api_key)
            jina_antibot_detection = detect_antibot_html(content)
            if jina_antibot_detection:
                raise WebSaveScriptError(
                    "FetchError",
                    classify_web_save_failure(
                        upstream_error_type="FetchError",
                        upstream_message=(
                            f"Jina fallback returned anti-bot "
                            f"challenge: {jina_antibot_detection.reason}"
                        ),
                        url=url,
                        target_url=target_url,
                        mode=web_save_mode,
                        local_parse_error=local_parse_error,
                        local_antibot_detection=local_antibot_detection,
                        local_antibot_stage=local_antibot_stage,
                        local_antibot_rule_id=local_antibot_rule_id,
                        upstream_antibot_detection=jina_antibot_detection,
                        fallback_outcome="blocked_content",
                    ),
                )
            parsed_metadata, cleaned_content = parse_jina_metadata(content)
            source = parsed_metadata.get("url_source") or target_url
            wsj_flags = {"paywalled": False, "truncated": False}
            raw_summary = _summarize_markdown(content)
            if JinaService is not None:
                cleaned_content = JinaService.clean_markdown_for_source(
                    cleaned_content, source
                )
            fastcompany_preview = _extract_fastcompany_preview_markdown(
                cleaned_content, source=source
            )
            if fastcompany_preview:
                cleaned_content = fastcompany_preview
            if apply_wsj_content_guards is not None:
                cleaned_content, wsj_flags = apply_wsj_content_guards(
                    domain=urlparse(source).netloc.lower().strip("."),
                    raw_html="",
                    marker_markdown=content,
                    markdown=cleaned_content,
                )
            cleaned_summary = _summarize_markdown(cleaned_content)
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
            reading_time = _resolve_jina_reading_time(
                metadata=parsed_metadata,
                source=source,
                fallback_url=target_url,
                word_count=word_count,
            )
            domain = urlparse(source).netloc
            tags = extract_tags(cleaned_content, domain, title)
            logger.info(
                (
                    "web-save fallback result url=%s source=%s provider=jina "
                    "raw_chars=%s clean_chars=%s raw_noise=%s clean_noise=%s "
                    "raw_link_density_pct=%s clean_link_density_pct=%s "
                    "raw_trunc_markers=%s clean_trunc_markers=%s "
                    "clean_links=%s clean_images=%s word_count=%s "
                    "truncated=%s paywalled=%s"
                ),
                url,
                source,
                raw_summary["chars"],
                cleaned_summary["chars"],
                raw_summary["noise_hits"],
                cleaned_summary["noise_hits"],
                raw_summary["link_density_pct"],
                cleaned_summary["link_density_pct"],
                raw_summary["truncation_hits"],
                cleaned_summary["truncation_hits"],
                cleaned_summary["links"],
                cleaned_summary["images"],
                word_count,
                wsj_flags["truncated"],
                wsj_flags["paywalled"],
            )
            if _is_low_quality_reuters_fallback(
                source=source,
                cleaned_content=cleaned_content,
                summary=cleaned_summary,
            ):
                logger.info(
                    (
                        "web-save fallback rejected source=%s provider=jina "
                        "reason=low_quality_reuters_shell clean_noise=%s "
                        "link_density_pct=%s prose_blocks=%s"
                    ),
                    source,
                    cleaned_summary["noise_hits"],
                    cleaned_summary["link_density_pct"],
                    _count_reuters_prose_blocks(cleaned_content),
                )
                raise WebSaveScriptError(
                    "FetchError",
                    classify_web_save_failure(
                        upstream_error_type="FetchError",
                        upstream_message=(
                            "Jina fallback returned low-quality Reuters shell content"
                        ),
                        url=url,
                        target_url=target_url,
                        mode=web_save_mode,
                        local_parse_error=local_parse_error,
                        local_antibot_detection=local_antibot_detection,
                        local_antibot_stage=local_antibot_stage,
                        local_antibot_rule_id=local_antibot_rule_id,
                        upstream_antibot_detection=None,
                        fallback_outcome="blocked_content",
                    ),
                )
            if _is_low_quality_fastcompany_fallback(
                source=source,
                cleaned_content=cleaned_content,
                summary=cleaned_summary,
            ):
                logger.info(
                    (
                        "web-save fallback rejected source=%s provider=jina "
                        "reason=fastcompany_shell"
                    ),
                    source,
                )
                raise WebSaveScriptError(
                    "FetchError",
                    classify_web_save_failure(
                        upstream_error_type="FetchError",
                        upstream_message=(
                            "Jina fallback returned low-quality Fast Company "
                            "shell content"
                        ),
                        url=url,
                        target_url=target_url,
                        mode=web_save_mode,
                        local_parse_error=local_parse_error,
                        local_antibot_detection=local_antibot_detection,
                        local_antibot_stage=local_antibot_stage,
                        local_antibot_rule_id=local_antibot_rule_id,
                        fallback_outcome="blocked_content",
                    ),
                )
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
                    "reading_time": reading_time,
                    "tags": tags,
                    "paywalled": wsj_flags["paywalled"] or None,
                    "truncated": wsj_flags["truncated"] or None,
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
                    (
                        "Compare parse for %s: jina_len=%s local_len=%s "
                        "jina_title=%s local_title=%s fallback_elapsed_ms=%s"
                    ),
                    target_url,
                    len(cleaned_content),
                    len(local_parsed.content),
                    title,
                    local_parsed.title,
                    int((time.monotonic() - fallback_started_at) * 1000),
                )
        except WebSaveScriptError:
            raise
        except Exception as exc:
            if web_save_mode == "compare" and local_parsed is not None:
                logger.info("Compare parse failed for %s: %s", url, str(exc))
                parsed = local_parsed
            else:
                if local_parse_error:
                    fallback_outcome = (
                        "timeout"
                        if isinstance(exc, requests.exceptions.Timeout)
                        else None
                    )
                    raise WebSaveScriptError(
                        "FetchError",
                        classify_web_save_failure(
                            upstream_error_type=type(exc).__name__,
                            upstream_message=str(exc),
                            url=url,
                            target_url=target_url,
                            mode=web_save_mode,
                            local_parse_error=local_parse_error,
                            local_antibot_detection=local_antibot_detection,
                            local_antibot_stage=local_antibot_stage,
                            local_antibot_rule_id=local_antibot_rule_id,
                            upstream_antibot_detection=None,
                            fallback_outcome=fallback_outcome,
                        ),
                    ) from exc
                raise
    elif parsed is not None:
        title = parsed.title
        source = parsed.source
        published_at = parsed.published_at

    if parsed is None:
        raise WebSaveScriptError(
            "UnexpectedError",
            classify_web_save_failure(
                upstream_error_type="UnexpectedError",
                upstream_message="Failed to parse URL",
                url=url,
                target_url=target_url,
                mode=web_save_mode,
                local_parse_error=local_parse_error,
                local_antibot_detection=local_antibot_detection,
                local_antibot_stage=local_antibot_stage,
                local_antibot_rule_id=local_antibot_rule_id,
                upstream_antibot_detection=None,
                fallback_outcome=None,
            ),
        )

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        upsert_started_at = time.monotonic()
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
        logger.info(
            "web-save database upsert ok url=%s website_id=%s upsert_elapsed_ms=%s",
            url,
            website.id,
            int((time.monotonic() - upsert_started_at) * 1000),
        )
        favicon_url = parsed.favicon_url
        if favicon_url is None:
            try:
                favicon_url = extract_favicon_url(target_url)
            except Exception:
                favicon_url = None

        favicon_started_at = time.monotonic()
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
        logger.info(
            (
                "web-save script complete url=%s website_id=%s "
                "favicon_enabled=%s favicon_elapsed_ms=%s total_elapsed_ms=%s"
            ),
            url,
            website.id,
            bool(FaviconService is not None and favicon_url),
            int((time.monotonic() - favicon_started_at) * 1000),
            int((time.monotonic() - script_started_at) * 1000),
        )
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

    except WebSaveScriptError as e:
        error_output = {
            "success": False,
            "error": e.as_error(),
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except ValueError as e:
        classified = classify_web_save_failure(
            upstream_error_type="ValidationError",
            upstream_message=str(e),
            url=args.url,
            target_url=args.url,
            mode=os.getenv("WEB_SAVE_MODE", "local").lower().strip(),
        )
        error_output = {
            "success": False,
            "error": {
                "type": "ValidationError",
                "code": classified.get("code"),
                "message": classified.get("message"),
                "details": classified.get("details", {}),
                "suggestions": classified.get("suggestions", []),
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except requests.exceptions.RequestException as e:
        classified = classify_web_save_failure(
            upstream_error_type="FetchError",
            upstream_message=str(e),
            url=args.url,
            target_url=args.url,
            mode=os.getenv("WEB_SAVE_MODE", "local").lower().strip(),
        )
        error_output = {
            "success": False,
            "error": {
                "type": "FetchError",
                "code": classified.get("code"),
                "message": classified.get("message"),
                "details": classified.get("details", {}),
                "suggestions": classified.get("suggestions", []),
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
        classified = classify_web_save_failure(
            upstream_error_type="UnexpectedError",
            upstream_message=f"Unexpected error: {str(e)}",
            url=args.url,
            target_url=args.url,
            mode=os.getenv("WEB_SAVE_MODE", "local").lower().strip(),
        )
        error_output = {
            "success": False,
            "error": {
                "type": "UnexpectedError",
                "code": classified.get("code"),
                "message": classified.get("message"),
                "details": classified.get("details", {}),
                "suggestions": classified.get("suggestions", []),
            },
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
