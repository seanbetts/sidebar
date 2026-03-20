"""Reuters-specific article extraction helpers."""

from __future__ import annotations

import re
from copy import deepcopy
from urllib.parse import urlparse

from bs4 import BeautifulSoup, Tag

_TITLE_SUFFIX_RE = re.compile(r"\s*\|\s*Reuters\s*$", re.IGNORECASE)
_TRACKING_IMAGE_PATTERNS = (
    "sp.analytics.yahoo.com",
    "ad.gt/api/",
    "ids4.ad.gt/api/",
    "secure.adnxs.com/getuid",
    "u.openx.net/w/1.0/cm",
    "image2.pubmatic.com",
    "token.rubiconproject.com/token",
    "match.adsrvr.org/track/",
    "pixel.tapad.com/idsync/",
    "cm.g.doubleclick.net/pixel",
    "d.turn.com/r/dd/",
    "sync.go.sonobi.com/us",
    "ad.360yield.com/ux",
)
_DROP_HEADINGS = {
    "read next",
    "about reuters",
    "lseg products",
}
_DROP_EXACT_TEXT = {
    "purchase licensing rights",
    "report ad",
}


def is_reuters_article_url(url: str) -> bool:
    """Return True when the URL points at a Reuters article page."""
    parsed = urlparse(url)
    host = parsed.netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    if host != "reuters.com":
        return False
    path = parsed.path.strip("/")
    return bool(
        path and path.count("/") >= 1 and re.search(r"-\d{4}-\d{2}-\d{2}/?$", path)
    )


def extract_reuters_payload(raw_html: str, url: str) -> tuple[str, dict] | None:
    """Return cleaned Reuters article HTML and metadata overrides."""
    if not is_reuters_article_url(url):
        return None

    soup = BeautifulSoup(raw_html, "html.parser")
    article = soup.find("article")
    if not isinstance(article, Tag):
        return None

    cleaned_article = deepcopy(article)
    _cleanup_reuters_article(cleaned_article)

    if not cleaned_article.find("p"):
        return None

    title = _normalize_reuters_title(_extract_text(cleaned_article.find("h1")))
    authors = _extract_reuters_authors(cleaned_article)

    metadata = {
        "title": title,
        "author": ", ".join(authors) if authors else None,
        "image": None if cleaned_article.find("img") else None,
    }
    return str(cleaned_article), metadata


def _cleanup_reuters_article(article: Tag) -> None:
    """Remove Reuters-specific non-article descendants from an article subtree."""
    for img in list(article.find_all("img")):
        src = (img.get("src") or "").strip()
        if src.startswith("blob:") or any(
            pattern in src for pattern in _TRACKING_IMAGE_PATTERNS
        ):
            img.decompose()

    for anchor in list(article.find_all("a")):
        href = (anchor.get("href") or "").strip()
        text = anchor.get_text(" ", strip=True)
        if not href and not text:
            anchor.decompose()
            continue
        if text.lower() == "purchase licensing rights":
            parent = anchor.find_parent(["section", "div", "aside", "li"])
            (parent or anchor).decompose()

    for node in list(article.find_all(["section", "div", "aside", "nav", "ul"])):
        text = node.get_text(" ", strip=True)
        normalized = text.lower()
        heading = _extract_section_heading(node)
        if heading in _DROP_HEADINGS:
            node.decompose()
            continue
        if normalized in _DROP_EXACT_TEXT:
            node.decompose()
            continue
        if _looks_like_reuters_author_bio(node):
            node.decompose()
            continue

    for paragraph in list(article.find_all(["p", "span", "figcaption"])):
        normalized = paragraph.get_text(" ", strip=True).lower()
        if normalized in _DROP_EXACT_TEXT:
            paragraph.decompose()


def _extract_section_heading(node: Tag) -> str | None:
    for tag_name in ("h2", "h3", "h4", "strong"):
        heading = node.find(tag_name)
        if isinstance(heading, Tag):
            text = heading.get_text(" ", strip=True).lower()
            if text:
                return text
    return None


def _looks_like_reuters_author_bio(node: Tag) -> bool:
    text = node.get_text(" ", strip=True).lower()
    if "reports on" not in text and "correspondent at reuters" not in text:
        return False
    author_links = [
        anchor
        for anchor in node.find_all("a", href=True)
        if "/authors/" in (anchor.get("href") or "")
    ]
    return bool(author_links)


def _extract_reuters_authors(article: Tag) -> list[str]:
    authors: list[str] = []
    seen: set[str] = set()
    for anchor in article.find_all("a", href=True):
        href = anchor.get("href") or ""
        if "/authors/" not in href:
            continue
        text = anchor.get_text(" ", strip=True)
        if not text or text.lower() in seen:
            continue
        seen.add(text.lower())
        authors.append(text)
    return authors


def _extract_text(node: Tag | None) -> str | None:
    if not isinstance(node, Tag):
        return None
    text = node.get_text(" ", strip=True)
    return text or None


def _normalize_reuters_title(value: str | None) -> str | None:
    if not value:
        return None
    cleaned = _TITLE_SUFFIX_RE.sub("", value).strip()
    return cleaned or None
