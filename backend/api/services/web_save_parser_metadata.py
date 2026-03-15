"""Fetch and metadata helpers for local web-save parsing."""

from __future__ import annotations

from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

from api.services.web_save_constants import USER_AGENT
from api.services.web_save_parser_fallback import raise_antibot_fallback_if_needed
from api.services.web_save_parser_html import decode_html_response
from api.services.web_save_parser_utils import clean_metadata_value, ensure_url
from api.services.web_save_rendering import render_html_with_playwright


def _attribute_string(value: str | list[str] | None) -> str | None:
    """Normalize BeautifulSoup attribute values to plain strings."""
    return value if isinstance(value, str) else None


def fetch_html(url: str, *, timeout: int = 30) -> tuple[str, str, bool]:
    """Fetch raw HTML and return (html, final_url, used_js_rendering).

    May raise LocalParseFallbackError when the Playwright fallback produces
    anti-bot challenge HTML.
    """
    headers = {"User-Agent": USER_AGENT}
    try:
        response = requests.get(url, headers=headers, timeout=timeout)
        response.raise_for_status()
        return decode_html_response(response), str(response.url), False
    except requests.HTTPError as exc:
        status_code = None
        if exc.response is not None:
            status_code = exc.response.status_code
        if status_code in {401, 403, 429}:
            html, final_url = render_html_with_playwright(
                url,
                timeout=timeout * 1000,
                wait_until="domcontentloaded",
            )
            raise_antibot_fallback_if_needed(html, stage="playwright")
            return html, final_url, True
        raise


def _rel_matches(rel_value: str | list[str] | None, target: str) -> bool:
    """Return True when rel_value includes all tokens from target."""
    if not rel_value:
        return False
    if isinstance(rel_value, str):
        rel_tokens = rel_value.lower().split()
    else:
        rel_tokens = [str(token).lower() for token in rel_value]
    target_tokens = target.lower().split()
    return all(token in rel_tokens for token in target_tokens)


def _favicon_exists(url: str, *, timeout: int = 8) -> bool:
    """Return True if a favicon URL responds successfully."""
    headers = {"User-Agent": USER_AGENT}
    try:
        response = requests.head(
            url, headers=headers, timeout=timeout, allow_redirects=True
        )
        if response.status_code == 405:
            response.close()
            response = requests.get(
                url, headers=headers, timeout=timeout, allow_redirects=True, stream=True
            )
        ok = 200 <= response.status_code < 400
        response.close()
        return ok
    except requests.RequestException:
        return False


def extract_metadata(html: str, url: str) -> dict:
    """Extract basic metadata from HTML."""
    soup = BeautifulSoup(html, "html.parser")

    def find_meta(names: list[str], attrs: tuple[str, ...]) -> str | None:
        for name in names:
            for attr in attrs:
                tag = soup.find("meta", attrs={attr: name})
                if not tag:
                    continue
                content = _attribute_string(tag.get("content"))
                if content:
                    return content.strip()
        return None

    title = clean_metadata_value(
        find_meta(["og:title", "twitter:title"], ("property", "name"))
        or (soup.title.string.strip() if soup.title and soup.title.string else None)
    )
    author = clean_metadata_value(
        find_meta(["author", "article:author", "parsely-author"], ("name", "property"))
    )
    published = clean_metadata_value(
        find_meta(
            [
                "article:published_time",
                "og:pubdate",
                "pubdate",
                "date",
                "parsely-pub-date",
            ],
            ("property", "name"),
        )
    )
    if not published:
        semantic_published = (
            soup.select_one("article time[datetime]")
            or soup.select_one("main time[datetime]")
            or soup.select_one("header time[datetime]")
            or soup.select_one("time[datetime]")
            or soup.select_one("[itemprop='datePublished'][datetime]")
            or soup.select_one("[itemprop='datePublished'][content]")
        )
        if semantic_published is not None:
            published = clean_metadata_value(
                _attribute_string(semantic_published.get("datetime"))
                or _attribute_string(semantic_published.get("content"))
                or semantic_published.get_text(" ", strip=True)
            )
    image = clean_metadata_value(
        find_meta(["og:image", "twitter:image"], ("property", "name"))
    )

    canonical = None
    canonical_tag = soup.find("link", rel="canonical")
    if canonical_tag:
        canonical = clean_metadata_value(_attribute_string(canonical_tag.get("href")))

    favicon = None
    for rel in (
        "icon",
        "shortcut icon",
        "apple-touch-icon",
        "apple-touch-icon-precomposed",
    ):
        link = soup.find("link", rel=lambda value, rel=rel: _rel_matches(value, rel))
        if link:
            favicon = clean_metadata_value(_attribute_string(link.get("href")))
            if favicon:
                break

    return {
        "title": title,
        "author": author,
        "published": published,
        "canonical": canonical or url,
        "image": image,
        "favicon": favicon,
    }


def resolve_favicon_url(raw_favicon: str | None, source_url: str) -> str | None:
    """Resolve a favicon URL relative to the source URL with fallbacks."""
    if raw_favicon:
        resolved = urljoin(source_url, raw_favicon)
        parsed = urlparse(resolved)
        if parsed.scheme in {"http", "https"}:
            return resolved
        return None

    parsed_source = urlparse(source_url)
    if not parsed_source.scheme or not parsed_source.netloc:
        return None
    fallback = f"{parsed_source.scheme}://{parsed_source.netloc}/favicon.ico"
    if _favicon_exists(fallback):
        return fallback
    return None


def extract_favicon_url(url: str, *, timeout: int = 15) -> str | None:
    """Fetch HTML and resolve a favicon URL without full parsing."""
    normalized = ensure_url(url)
    try:
        html, final_url, _ = fetch_html(normalized, timeout=timeout)
    except requests.RequestException:
        return None
    metadata = extract_metadata(html, final_url)
    return resolve_favicon_url(metadata.get("favicon"), final_url)
