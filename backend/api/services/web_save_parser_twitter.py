"""X/Twitter post snapshot helpers for web-save parsing."""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote_plus, urlparse

import requests
from bs4 import BeautifulSoup
from markdownify import MarkdownConverter

from api.services.web_save_constants import USER_AGENT


@dataclass(frozen=True)
class TwitterStatusSnapshot:
    """Compact saved representation for a public X/Twitter status URL."""

    title: str
    markdown: str
    source_url: str
    author: str | None


class _TwitterMarkdownConverter(MarkdownConverter):
    def convert_p(self, el, text, parent_tags):
        return f"{text.strip()}\n\n" if text.strip() else ""


def _html_to_markdown(html: str) -> str:
    converter = _TwitterMarkdownConverter(heading_style="ATX")
    return converter.convert(html).strip()


def extract_twitter_status_id(url: str) -> str | None:
    """Return the numeric status ID from an X/Twitter post URL."""
    parsed = urlparse(url)
    host = parsed.netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    if host not in {"x.com", "twitter.com", "mobile.x.com", "mobile.twitter.com"}:
        return None

    segments = [segment for segment in parsed.path.split("/") if segment]
    for index, segment in enumerate(segments[:-1]):
        if segment == "status" and segments[index + 1].isdigit():
            return segments[index + 1]
    return None


def _extract_handle_from_url(url: str | None) -> str | None:
    if not url:
        return None
    segments = [segment for segment in urlparse(url).path.split("/") if segment]
    for segment in segments:
        if segment not in {"i", "web", "status"}:
            return segment.lstrip("@") or None
    return None


def build_canonical_twitter_status_url(url: str, *, handle: str | None) -> str | None:
    """Return a canonical X status URL for the given post."""
    status_id = extract_twitter_status_id(url)
    if not status_id:
        return None
    if handle:
        return f"https://x.com/{handle}/status/{status_id}"
    return f"https://x.com/i/web/status/{status_id}"


def _build_snapshot_title(text: str, *, handle: str | None) -> str:
    normalized = " ".join(text.split())
    if normalized:
        return normalized[:117] + "..." if len(normalized) > 120 else normalized
    if handle:
        return f"Post by @{handle}"
    return "Post on X"


def fetch_twitter_status_snapshot(
    url: str, *, timeout: int = 8
) -> TwitterStatusSnapshot | None:
    """Fetch an auth-free X/Twitter post snapshot via the public oEmbed endpoint."""
    canonical_url = build_canonical_twitter_status_url(
        url, handle=_extract_handle_from_url(url)
    )
    if not canonical_url:
        return None

    oembed_url = (
        "https://publish.twitter.com/oembed"
        f"?url={quote_plus(canonical_url)}&omit_script=true&dnt=true"
    )
    try:
        response = requests.get(
            oembed_url,
            headers={"User-Agent": USER_AGENT},
            timeout=timeout,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception:
        return None

    html = payload.get("html")
    if not html:
        return None

    soup = BeautifulSoup(html, "html.parser")
    blockquote = soup.find("blockquote", class_="twitter-tweet")
    if blockquote is None:
        return None

    content_tag = blockquote.find("p")
    if content_tag is None:
        return None

    text_markdown = _html_to_markdown(str(content_tag)).strip()
    if not text_markdown:
        return None
    title_text = content_tag.get_text(" ", strip=True)

    author_name = payload.get("author_name") or None
    author_url = payload.get("author_url") or None
    handle = _extract_handle_from_url(author_url) or _extract_handle_from_url(url)
    source_url = build_canonical_twitter_status_url(url, handle=handle) or canonical_url

    published_label = None
    for anchor in blockquote.find_all("a"):
        href = anchor.get("href") or ""
        if "/status/" in href:
            published_label = anchor.get_text(" ", strip=True) or None

    author_bits: list[str] = []
    if author_name:
        if author_url:
            author_bits.append(f"[{author_name}]({author_url})")
        else:
            author_bits.append(author_name)
    if handle:
        author_bits.append(f"@{handle}")

    blocks: list[str] = []
    if author_bits or published_label:
        header_lines: list[str] = []
        if author_bits:
            header_lines.append(" ".join(author_bits))
        if published_label:
            header_lines.append(published_label)
        blocks.append("\n".join(header_lines))
    blocks.append(text_markdown)
    blocks.append(f"[View on X]({source_url})")

    return TwitterStatusSnapshot(
        title=_build_snapshot_title(title_text, handle=handle),
        markdown="\n\n".join(blocks).strip(),
        source_url=source_url,
        author=author_name,
    )
