"""Apple News helper logic for web-save parsing."""

from __future__ import annotations

import logging
import re
from collections.abc import Callable
from urllib.parse import urlparse

from bs4 import BeautifulSoup

APPLE_NEWS_REDIRECT_PATTERN = re.compile(
    r'redirectToUrl(?:AfterTimeout)?\("(?P<url>https?://[^"]+)"'
)


def is_apple_news_host(host: str | None) -> bool:
    """Return True when host belongs to apple.news."""
    normalized = (host or "").lower().strip(".")
    return normalized == "apple.news" or normalized.endswith(".apple.news")


def extract_apple_news_publisher_url(html: str) -> str | None:
    """Extract the publisher URL from an Apple News wrapper page."""
    if not html:
        return None
    redirect_match = APPLE_NEWS_REDIRECT_PATTERN.search(html)
    if redirect_match:
        return redirect_match.group("url").replace("\\/", "/")

    soup = BeautifulSoup(html, "html.parser")
    for anchor in soup.select("div.inner-content p a[href]"):
        href = str(anchor.get("href") or "").strip()
        if not href.startswith(("http://", "https://")):
            continue
        parsed_href = urlparse(href)
        if is_apple_news_host(parsed_href.netloc):
            continue
        normalized_path = parsed_href.path.rstrip("/")
        if parsed_href.netloc.lower().endswith("apple.com") and normalized_path in {
            "",
            "/news",
        }:
            continue
        return href
    return None


def maybe_unwrap_apple_news(
    *,
    html: str,
    final_url: str,
    used_js_rendering: bool,
    timeout: int,
    fetch_html: Callable[[str, int], tuple[str, str, bool]],
    logger: logging.Logger,
) -> tuple[str, str, bool]:
    """Fetch and return publisher HTML when the input is an Apple News wrapper."""
    if not is_apple_news_host(urlparse(final_url).netloc):
        return html, final_url, used_js_rendering

    publisher_url = extract_apple_news_publisher_url(html)
    if not publisher_url:
        return html, final_url, used_js_rendering

    logger.info(
        "web-save apple-news unwrap source=%s publisher=%s",
        final_url,
        publisher_url,
    )
    publisher_html, publisher_final_url, publisher_used_js_rendering = fetch_html(
        publisher_url, timeout
    )
    return (
        publisher_html,
        publisher_final_url,
        used_js_rendering or publisher_used_js_rendering,
    )
