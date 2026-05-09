"""Financial Times-specific parsing helpers."""

from __future__ import annotations

import json
from urllib.parse import urlparse

from bs4 import BeautifulSoup


def extract_ft_barrier_payload(
    raw_html: str,
    url: str,
) -> dict[str, str | None] | None:
    """Return FT barrier metadata when the page is a paywall shell, not an article."""
    host = urlparse(url).netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    if host != "ft.com":
        return None

    soup = BeautifulSoup(raw_html, "html.parser")
    if not _looks_like_ft_barrier_page(soup):
        return None

    jsonld_article = _extract_ft_jsonld_article(soup)
    description = _meta_content(soup, "og:description")
    title = (
        jsonld_article.get("headline")
        or _meta_content(soup, "og:title")
        or _normalize_text(soup.select_one("h1"))
    )
    image = _meta_content(soup, "og:image") or jsonld_article.get("image")

    return {
        "title": title,
        "author": jsonld_article.get("author"),
        "published": jsonld_article.get("published"),
        "image": image,
        "preview": description,
    }


def _looks_like_ft_barrier_page(soup: BeautifulSoup) -> bool:
    """Return True when the FT HTML is a subscription barrier shell."""
    title_text = _normalize_text(soup.title)
    page_text = " ".join(soup.get_text(" ", strip=True).split()).lower()
    if title_text and title_text.lower() == "subscribe to read":
        return True
    barrier_markers = (
        "subscribe to unlock this article",
        "keep reading for",
        "complete digital access to quality ft journalism",
        "try unlimited access",
    )
    return any(marker in page_text for marker in barrier_markers)


def _extract_ft_jsonld_article(soup: BeautifulSoup) -> dict[str, str | None]:
    """Extract headline, author, image, and publish time from FT JSON-LD."""
    for script in soup.select('script[type="application/ld+json"]'):
        raw_text = script.string or script.get_text()
        if not raw_text:
            continue
        try:
            payload = json.loads(raw_text)
        except json.JSONDecodeError:
            continue
        if not isinstance(payload, dict) or payload.get("@type") != "NewsArticle":
            continue
        image = payload.get("image")
        image_url = image.get("url") if isinstance(image, dict) else image
        return {
            "headline": payload.get("headline")
            if isinstance(payload.get("headline"), str)
            else None,
            "author": _extract_author(payload.get("author")),
            "published": payload.get("datePublished")
            if isinstance(payload.get("datePublished"), str)
            else None,
            "image": image_url if isinstance(image_url, str) else None,
        }
    return {}


def _extract_author(author_value: object) -> str | None:
    """Extract a normalized author string from FT JSON-LD."""
    if isinstance(author_value, dict):
        name = author_value.get("name")
        return name if isinstance(name, str) else None
    if isinstance(author_value, list):
        names: list[str] = []
        for entry in author_value:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            if isinstance(name, str):
                names.append(name)
        return ", ".join(names) if names else None
    return None


def _meta_content(soup: BeautifulSoup, property_name: str) -> str | None:
    """Return a meta content string for an FT metadata property."""
    tag = soup.find("meta", attrs={"property": property_name})
    if tag is None:
        return None
    content = tag.get("content")
    return content.strip() if isinstance(content, str) and content.strip() else None


def _normalize_text(node: object) -> str | None:
    """Normalize text content from a BeautifulSoup node."""
    if node is None:
        return None
    text_getter = getattr(node, "get_text", None)
    if text_getter is None:
        return None
    text = " ".join(text_getter(" ", strip=True).split())
    return text or None
