"""Local parsing utilities for the web-save skill."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlparse

import re
import requests
import yaml
from bs4 import BeautifulSoup
from markdownify import markdownify
from readability import Document

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)


@dataclass(frozen=True)
class ParsedPage:
    """Parsed page payload for saving."""

    title: str
    content: str
    source: str
    published_at: Optional[datetime]


def ensure_url(value: str) -> str:
    """Ensure URL has a scheme."""
    if value.startswith(("http://", "https://")):
        return value
    return f"https://{value}"


def fetch_html(url: str, *, timeout: int = 30) -> tuple[str, str]:
    """Fetch raw HTML and return (html, final_url)."""
    headers = {"User-Agent": USER_AGENT}
    response = requests.get(url, headers=headers, timeout=timeout)
    response.raise_for_status()
    return response.text, str(response.url)


def extract_metadata(html: str, url: str) -> dict:
    """Extract basic metadata from HTML."""
    soup = BeautifulSoup(html, "html.parser")

    def find_meta(names: list[str], attrs: tuple[str, ...]) -> Optional[str]:
        for name in names:
            for attr in attrs:
                tag = soup.find("meta", attrs={attr: name})
                if tag and tag.get("content"):
                    return tag["content"].strip()
        return None

    title = (
        find_meta(["og:title", "twitter:title"], ("property", "name"))
        or (soup.title.string.strip() if soup.title and soup.title.string else None)
    )
    author = find_meta(
        ["author", "article:author", "parsely-author"], ("name", "property")
    )
    published = find_meta(
        ["article:published_time", "og:pubdate", "pubdate", "date", "parsely-pub-date"],
        ("property", "name"),
    )

    canonical = None
    canonical_tag = soup.find("link", rel="canonical")
    if canonical_tag and canonical_tag.get("href"):
        canonical = canonical_tag["href"].strip()

    return {
        "title": title,
        "author": author,
        "published": published,
        "canonical": canonical or url,
    }


def parse_datetime(value: Optional[str]) -> Optional[datetime]:
    """Parse ISO-like datetime strings."""
    if not value:
        return None
    cleaned = value.strip()
    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


def html_to_markdown(html: str) -> str:
    """Convert HTML to Markdown."""
    return markdownify(html, heading_style="ATX").strip()


def compute_word_count(markdown_text: str) -> int:
    """Estimate word count from markdown."""
    words = re.findall(r"\b\w+\b", markdown_text)
    return len(words)


def reading_time_minutes(word_count: int, *, wpm: int = 200) -> int:
    """Compute reading time in minutes."""
    if word_count <= 0:
        return 1
    return max(1, round(word_count / wpm))


def build_frontmatter(markdown_text: str, *, meta: dict) -> str:
    """Build YAML frontmatter + markdown output."""
    payload = {key: value for key, value in meta.items() if value is not None}
    frontmatter = yaml.safe_dump(
        payload, sort_keys=False, allow_unicode=False
    ).strip()
    return f"---\n{frontmatter}\n---\n\n{markdown_text.strip()}\n"


def parse_url_local(url: str, *, timeout: int = 30) -> ParsedPage:
    """Parse a URL locally into Markdown with frontmatter."""
    normalized = ensure_url(url)
    html, final_url = fetch_html(normalized, timeout=timeout)
    metadata = extract_metadata(html, final_url)

    document = Document(html)
    article_html = document.summary(html_partial=True)
    markdown = html_to_markdown(article_html)
    if not markdown:
        raise ValueError("No readable content extracted")

    title = metadata.get("title") or document.short_title() or document.title() or urlparse(final_url).netloc
    published_at = parse_datetime(metadata.get("published"))
    word_count = compute_word_count(markdown)
    frontmatter_meta = {
        "source": metadata.get("canonical") or final_url,
        "title": title,
        "author": metadata.get("author"),
        "published_date": published_at.isoformat() if published_at else None,
        "domain": urlparse(final_url).netloc,
        "word_count": word_count,
        "reading_time": f"{reading_time_minutes(word_count)} min",
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }

    content = build_frontmatter(markdown, meta=frontmatter_meta)

    return ParsedPage(
        title=title,
        content=content,
        source=metadata.get("canonical") or final_url,
        published_at=published_at,
    )
