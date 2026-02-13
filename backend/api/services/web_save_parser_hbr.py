"""HBR-specific extraction helpers for web-save parsing."""

from __future__ import annotations

import json
import re
from html import escape, unescape
from typing import Any

from bs4 import BeautifulSoup

_HEADING_MARKER = "[[HBR_HEADING]]"
_HEADING_START = (
    r"(?:Use|Speak|Show|Name|Highlight|Build|Focus|Start|Stop|Lead|Make|Ask|Set|"
    r"Create|Clarify|Define|Frame|Practice|Explain|Share|Keep|Think|Reframe|Shift|"
    r"Move|Treat|Prioritize|Communicate|Align|Own|Measure)"
)
_HEADING_WORD = (
    r"(?:[\"'“”]?[A-Z][A-Za-z0-9'’“”\-]*|to|and|the|of|your|for|in|on|at|a|an|"
    r"me|then)"
)
_SECTION_HEADING_RE = re.compile(
    rf"(?:(?<=[.!?])|(?<=[.!?][\"'”]))\s+"
    rf"(({_HEADING_START}(?:\s+{_HEADING_WORD}){{1,6}}))\s+(?=[A-Z])"
)
_SENTENCE_BOUNDARY_RE = re.compile(r'([.!?]["\'”]?)\s+(?=[A-Z“"])')


def _normalize_text(value: str | None) -> str | None:
    """Normalize whitespace and entities in extracted text."""
    if not isinstance(value, str):
        return None
    cleaned = " ".join(unescape(value).replace("\xa0", " ").split())
    return cleaned or None


def _parse_json_payload(value: str | None) -> Any:
    """Safely parse JSON payload strings."""
    if not value:
        return None
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return None


def _is_article_type(value: Any) -> bool:
    """Return True when schema @type indicates an article-like object."""
    if isinstance(value, str):
        return "article" in value.lower()
    if isinstance(value, list):
        return any(
            isinstance(item, str) and "article" in item.lower() for item in value
        )
    return False


def _iter_jsonld_items(payload: Any) -> list[dict[str, Any]]:
    """Return dictionary candidates from a JSON-LD payload."""
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if not isinstance(payload, dict):
        return []
    if isinstance(payload.get("@graph"), list):
        return [item for item in payload["@graph"] if isinstance(item, dict)]
    return [payload]


def _extract_author(value: Any) -> str | None:
    """Extract an author name from schema.org author fields."""
    if isinstance(value, str):
        return _normalize_text(value)
    if isinstance(value, dict):
        return _normalize_text(value.get("name"))
    if isinstance(value, list):
        for item in value:
            author = _extract_author(item)
            if author:
                return author
    return None


def _extract_hbr_article_from_jsonld(
    soup: BeautifulSoup,
) -> dict[str, str | None] | None:
    """Extract article text and metadata from JSON-LD scripts."""
    for script in soup.find_all("script", attrs={"type": "application/ld+json"}):
        payload = _parse_json_payload(script.string or script.get_text())
        if payload is None:
            continue
        for item in _iter_jsonld_items(payload):
            if not _is_article_type(item.get("@type")):
                continue
            article_body = _normalize_text(item.get("articleBody"))
            if not article_body:
                continue
            return {
                "article_body": article_body,
                "title": _normalize_text(item.get("headline")),
                "author": _extract_author(item.get("author")),
                "published": _normalize_text(item.get("datePublished")),
                "canonical": _normalize_text(item.get("url")),
            }
    return None


def _extract_hbr_article_from_next_data(
    soup: BeautifulSoup,
) -> dict[str, str | None] | None:
    """Extract article text and metadata from Next.js hydration payload."""
    script = soup.find("script", id="__NEXT_DATA__")
    payload = _parse_json_payload(script.string if script else None)
    if not isinstance(payload, dict):
        return None
    article = ((payload.get("props") or {}).get("pageProps") or {}).get("article") or {}
    if not isinstance(article, dict):
        return None
    article_body = _normalize_text(article.get("articleBody"))
    if not article_body:
        return None
    return {
        "article_body": article_body,
        "title": _normalize_text(article.get("title")),
        "author": _extract_author(article.get("authors") or article.get("author")),
        "published": _normalize_text(article.get("published")),
        "canonical": None,
    }


def _build_body_html(article_body: str) -> str:
    """Convert plain article body text into simple paragraph and heading HTML."""
    marked = _SECTION_HEADING_RE.sub(rf"\n\n{_HEADING_MARKER}\1\n\n", article_body)
    blocks = [block.strip() for block in marked.split("\n\n") if block.strip()]
    if not blocks:
        return f"<div><p>{escape(article_body)}</p></div>"

    def _split_sentences(text: str) -> list[str]:
        sentences: list[str] = []
        start = 0
        for match in _SENTENCE_BOUNDARY_RE.finditer(text):
            end = match.end(1)
            sentence = text[start:end].strip()
            if sentence:
                sentences.append(sentence)
            start = match.end()
        tail = text[start:].strip()
        if tail:
            sentences.append(tail)
        return sentences

    def _split_oversized_sentence(sentence: str, *, max_words: int = 90) -> list[str]:
        words = sentence.split()
        if len(words) <= max_words:
            return [sentence]
        return [
            " ".join(words[index : index + max_words])
            for index in range(0, len(words), max_words)
        ]

    def _paragraphize_block(text: str) -> list[str]:
        raw_sentences = _split_sentences(text)
        sentences: list[str] = []
        for sentence in raw_sentences:
            sentences.extend(_split_oversized_sentence(sentence))
        if not sentences:
            return [text]

        paragraphs: list[str] = []
        current: list[str] = []
        current_words = 0
        target_words = 55
        min_words = 25
        for sentence in sentences:
            words = len(sentence.split())
            if (
                current
                and current_words >= min_words
                and current_words + words > target_words
            ):
                paragraphs.append(" ".join(current).strip())
                current = [sentence]
                current_words = words
                continue
            current.append(sentence)
            current_words += words
        if current:
            paragraphs.append(" ".join(current).strip())
        return [paragraph for paragraph in paragraphs if paragraph]

    html_parts: list[str] = ["<div>"]
    for block in blocks:
        if block.startswith(_HEADING_MARKER):
            heading = block[len(_HEADING_MARKER) :].strip()
            if heading:
                html_parts.append(f"<h2>{escape(heading)}</h2>")
            continue
        for paragraph in _paragraphize_block(block):
            html_parts.append(f"<p>{escape(paragraph)}</p>")
    html_parts.append("</div>")
    return "".join(html_parts)


def extract_hbr_body_html(raw_html: str) -> tuple[str, dict[str, str]] | None:
    """Extract HBR full article body from JSON payloads when DOM is truncated."""
    if not raw_html:
        return None

    soup = BeautifulSoup(raw_html, "html.parser")
    payload = _extract_hbr_article_from_jsonld(soup)
    if payload is None:
        payload = _extract_hbr_article_from_next_data(soup)
    if payload is None:
        return None

    article_body = payload.get("article_body")
    if not article_body or len(article_body) < 200:
        return None

    html_body = _build_body_html(article_body)
    metadata = {
        "title": payload.get("title") or "",
        "author": payload.get("author") or "",
        "published": payload.get("published") or "",
        "canonical": payload.get("canonical") or "",
    }
    return html_body, metadata
