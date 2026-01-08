"""YouTube-related parsing helpers for web-save."""

from __future__ import annotations

import json
import re
from typing import Any
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup
from lxml import html as lxml_html

from api.services.web_save_includes import find_insertion_point
from api.services.web_save_parser_html import _safe_html_tostring, _safe_html_tree

YOUTUBE_ID_PATTERN = re.compile(
    r"(?:youtube\.com/(?:watch\?v=|embed/)|youtu\.be/)([A-Za-z0-9_-]+)"
)
YOUTUBE_EMBED_PATTERN = re.compile(
    r"(?:youtube(?:-nocookie)?\.com/(?:embed/|v/))([A-Za-z0-9_-]+)"
)
YOUTUBE_RAW_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{11}$")
YOUTUBE_EMBED_TAGS = {
    "iframe",
    "lite-youtube",
    "amp-youtube",
    "youtube-player",
    "yt-embed",
}
YOUTUBE_ID_ATTRS = {
    "data-youtube-id",
    "data-youtubeid",
    "data-yt-id",
    "data-ytid",
    "data-video-id",
    "data-videoid",
    "data-video",
    "video-id",
    "videoid",
}
YOUTUBE_URL_ATTRS = (
    "src",
    "data-src",
    "data-lazy-src",
    "data-original",
    "data-url",
    "data-embed",
    "data-embed-url",
    "data-video-url",
    "data-youtube-url",
    "data-yt-url",
    "href",
)
YOUTUBE_BLOCKED_TOKENS = (
    "ad",
    "ads",
    "advert",
    "advertisement",
    "sponsor",
    "sponsored",
    "promo",
    "promoted",
    "cookie",
    "consent",
)
JSONLD_ARTICLE_TYPES = {
    "Article",
    "NewsArticle",
    "BlogPosting",
    "Report",
    "LiveBlogPosting",
}
JSONLD_MEDIA_PATTERN = re.compile(
    r"\[(?:Media|Video):\s*(https?://[^\]]+)\]", re.IGNORECASE
)
JSONLD_YOUTUBE_PATTERN = re.compile(
    r"https?://(?:www\.)?(?:youtube\.com/watch\?v=|youtu\.be/)[A-Za-z0-9_-]+",
    re.IGNORECASE,
)


def extract_youtube_video_id(url: str) -> str | None:
    """Extract a YouTube video id from a URL."""
    match = YOUTUBE_ID_PATTERN.search(url)
    return match.group(1) if match else None


def extract_youtube_embed_id(url: str) -> str | None:
    """Extract a YouTube embed id from a URL."""
    match = YOUTUBE_EMBED_PATTERN.search(url)
    return match.group(1) if match else None


def _extract_youtube_id_from_text(text: str) -> str | None:
    if not text:
        return None
    scan_text = text.replace("\\/", "/")
    match = YOUTUBE_ID_PATTERN.search(scan_text)
    if match:
        return match.group(1)
    match = YOUTUBE_EMBED_PATTERN.search(scan_text)
    if match:
        return match.group(1)
    return None


def _extract_youtube_id_from_element(
    elem: lxml_html.HtmlElement, base_url: str
) -> str | None:
    for attr in YOUTUBE_URL_ATTRS:
        value = elem.get(attr)
        if not value:
            continue
        normalized = urljoin(base_url, value)
        video_id = _extract_youtube_id_from_text(normalized)
        if video_id:
            return video_id
        video_id = _extract_youtube_id_from_text(value)
        if video_id:
            return video_id
    for _attr, value in elem.attrib.items():
        if not isinstance(value, str):
            continue
        if "youtube" in value or "youtu.be" in value:
            video_id = _extract_youtube_id_from_text(value)
            if video_id:
                return video_id
    for attr in YOUTUBE_ID_ATTRS:
        value = elem.get(attr)
        if not value:
            continue
        candidate = value.strip()
        if YOUTUBE_RAW_ID_PATTERN.fullmatch(candidate):
            return candidate
    return None


def _contains_blocked_token(value: str) -> bool:
    if not value:
        return False
    return bool(
        re.search(
            r"\b(ad|ads|advert|advertisement|sponsor|sponsored|promo|promoted)\b", value
        )
    )


def _is_blocked_youtube_embed(elem: lxml_html.HtmlElement) -> bool:
    for ancestor in elem.iterancestors():
        classes = " ".join(ancestor.get("class", [])).lower()
        ident = ancestor.get("id", "").lower()
        marker = f"{classes} {ident}"
        if any(token in marker for token in YOUTUBE_BLOCKED_TOKENS):
            return True
        for attr in ("aria-label", "role", "data-testid", "data-ad", "data-ad-unit"):
            value = (ancestor.get(attr) or "").lower()
            if _contains_blocked_token(value):
                return True
    return False


def _has_ancestor_class(elem: lxml_html.HtmlElement, class_name: str) -> bool:
    for ancestor in elem.iterancestors():
        classes = ancestor.get("class", "")
        if not classes:
            continue
        if class_name in classes.split():
            return True
    return False


def _is_verge_article_body_component(elem: lxml_html.HtmlElement) -> bool:
    for ancestor in elem.iterancestors():
        classes = ancestor.get("class", "")
        if not classes:
            continue
        tokens = classes.split()
        if "duet--article--article-body-component" in tokens:
            return True
    return False


def _is_within_article(elem: lxml_html.HtmlElement, has_article: bool) -> bool:
    if not has_article:
        return True
    for ancestor in elem.iterancestors():
        tag = ancestor.tag.lower() if isinstance(ancestor.tag, str) else ""
        if tag in {"article", "main"}:
            return True
        role = (ancestor.get("role") or "").lower()
        if role == "main":
            return True
    return False


def _is_likely_youtube_embed_element(elem: lxml_html.HtmlElement) -> bool:
    tag = elem.tag.lower() if isinstance(elem.tag, str) else ""
    if tag in YOUTUBE_EMBED_TAGS:
        return True
    if tag in {"a", "script", "style", "meta", "link"}:
        return False
    if any(elem.get(attr) for attr in YOUTUBE_ID_ATTRS):
        return True
    provider = (elem.get("data-provider") or elem.get("data-service") or "").lower()
    if "youtube" in provider:
        return True
    classes = " ".join(elem.get("class", [])).lower()
    return "youtube" in classes and ("player" in classes or "embed" in classes)


def _merge_youtube_anchors(
    primary: list[tuple[str, str]],
    secondary: list[tuple[str, str]],
) -> list[tuple[str, str]]:
    merged: list[tuple[str, str]] = []
    seen: set[str] = set()
    for group in (primary, secondary):
        for video_id, anchor_text in group:
            if video_id in seen:
                continue
            seen.add(video_id)
            merged.append((video_id, anchor_text))
    return merged


def _iter_jsonld_objects(raw_payload: Any) -> list[dict]:
    if isinstance(raw_payload, list):
        items: list[dict] = []
        for entry in raw_payload:
            items.extend(_iter_jsonld_objects(entry))
        return items
    if isinstance(raw_payload, dict):
        graph = raw_payload.get("@graph")
        if isinstance(graph, list):
            return _iter_jsonld_objects(graph)
        return [raw_payload]
    return []


def extract_youtube_anchors_from_jsonld(
    html: str,
) -> tuple[list[tuple[str, str]], set[str]]:
    """Extract YouTube anchor tuples and ids from JSON-LD script tags."""
    anchors: list[tuple[str, str]] = []
    video_ids: set[str] = set()
    soup = BeautifulSoup(html, "html.parser")
    for script in soup.find_all("script", attrs={"type": "application/ld+json"}):
        if not script.string:
            continue
        try:
            payload = json.loads(script.string)
        except json.JSONDecodeError:
            continue
        for obj in _iter_jsonld_objects(payload):
            raw_type = obj.get("@type")
            types: set[str] = set()
            if isinstance(raw_type, list):
                types = {str(entry) for entry in raw_type}
            elif isinstance(raw_type, str):
                types = {raw_type}
            if not types.intersection(JSONLD_ARTICLE_TYPES):
                continue
            article_body = obj.get("articleBody")
            if not isinstance(article_body, str):
                continue
            lines = [line.strip() for line in article_body.splitlines() if line.strip()]
            for idx, line in enumerate(lines):
                match = JSONLD_MEDIA_PATTERN.search(line)
                if match:
                    url = match.group(1)
                else:
                    url_match = JSONLD_YOUTUBE_PATTERN.search(line)
                    url = url_match.group(0) if url_match else None
                if not url:
                    continue
                video_id = extract_youtube_video_id(url)
                if not video_id:
                    continue
                anchor_text = ""
                if idx > 0:
                    anchor_text = lines[idx - 1]
                elif idx + 1 < len(lines):
                    anchor_text = lines[idx + 1]
                if anchor_text:
                    anchors.append((video_id, anchor_text[:200]))
                video_ids.add(video_id)
    return anchors, video_ids


def _iter_youtube_elements(
    raw_dom: lxml_html.HtmlElement, base_url: str
) -> list[tuple[str, lxml_html.HtmlElement]]:
    has_article = bool(raw_dom.cssselect("article"))
    is_verge = urlparse(base_url).netloc.endswith("theverge.com")
    is_9to5mac = urlparse(base_url).netloc.endswith("9to5mac.com")
    candidates: list[tuple[str, lxml_html.HtmlElement]] = []
    for elem in raw_dom.iter():
        if not isinstance(elem.tag, str):
            continue
        video_id = _extract_youtube_id_from_element(elem, base_url)
        if not video_id:
            continue
        if not _is_likely_youtube_embed_element(elem):
            continue
        if not _is_within_article(elem, has_article):
            continue
        if is_verge and not _is_verge_article_body_component(elem):
            continue
        if is_9to5mac and _has_ancestor_class(elem, "article__youtube-video"):
            continue
        if _is_blocked_youtube_embed(elem):
            continue
        candidates.append((video_id, elem))
    return candidates


def extract_youtube_video_ids_from_html(html: str, base_url: str) -> list[str]:
    """Return YouTube video ids discovered in HTML."""
    video_ids: list[str] = []
    soup = BeautifulSoup(html, "html.parser")
    for iframe in soup.find_all("iframe"):
        src = iframe.get("src")
        if not src:
            continue
        normalized = urljoin(base_url, src)
        video_id = extract_youtube_embed_id(normalized)
        if video_id:
            video_ids.append(video_id)
    scan_html = html.replace("\\/", "/")
    for match in YOUTUBE_EMBED_PATTERN.finditer(scan_html):
        video_ids.append(match.group(1))
    return video_ids


def extract_youtube_embeds(
    html: str, base_url: str, *, fallback_html: str | None = None
) -> list[str]:
    """Extract YouTube embed URLs from HTML."""
    sources = [html]
    if fallback_html and fallback_html is not html:
        sources.append(fallback_html)

    video_ids: list[str] = []
    for source_html in sources:
        video_ids.extend(extract_youtube_video_ids_from_html(source_html, base_url))

    seen = set()
    ordered: list[str] = []
    for video_id in video_ids:
        if video_id in seen:
            continue
        seen.add(video_id)
        ordered.append(f"https://www.youtube.com/watch?v={video_id}")
    return ordered


def extract_youtube_embed_urls_from_dom(
    raw_dom: lxml_html.HtmlElement, base_url: str
) -> list[str]:
    """Extract YouTube embed URLs while skipping ad/cookie embeds."""
    embed_urls: list[str] = []
    for video_id, _node in _iter_youtube_elements(raw_dom, base_url):
        embed_urls.append(f"https://www.youtube.com/watch?v={video_id}")
    seen: set[str] = set()
    ordered: list[str] = []
    for url in embed_urls:
        if url in seen:
            continue
        seen.add(url)
        ordered.append(url)
    return ordered


def replace_youtube_iframes_with_placeholders(
    html: str, base_url: str
) -> tuple[str, set[str]]:
    """Replace YouTube iframes with placeholders to preserve inline position."""
    tree = _safe_html_tree(html)
    embedded_ids: set[str] = set()

    for video_id, node in _iter_youtube_elements(tree, base_url):
        if video_id in embedded_ids:
            continue
        placeholder = lxml_html.Element("p")
        placeholder.text = f"YOUTUBE_EMBED:{video_id}"
        parent = node.getparent()
        if parent is not None:
            parent.replace(node, placeholder)
            embedded_ids.add(video_id)

    return _safe_html_tostring(tree, html), embedded_ids


def insert_youtube_placeholders(
    extracted_html: str, raw_dom: lxml_html.HtmlElement, base_url: str
) -> str:
    """Insert YouTube placeholders into extracted HTML."""
    extracted_tree = _safe_html_tree(extracted_html)
    body = extracted_tree.find(".//body") or extracted_tree
    existing_ids: set[str] = set()
    for elem in extracted_tree.iter():
        text = (elem.text or "").strip()
        if text.startswith("YOUTUBE_EMBED:"):
            existing_ids.add(text.split("YOUTUBE_EMBED:", 1)[1])

    anchor_by_id: dict[int, lxml_html.HtmlElement] = {}
    last_text_elem: lxml_html.HtmlElement | None = None
    for elem in raw_dom.iter():
        if not isinstance(elem.tag, str):
            continue
        text = elem.text_content().strip()
        if len(text) >= 5:
            last_text_elem = elem
        if last_text_elem is not None:
            anchor_by_id[id(elem)] = last_text_elem

    def find_anchor_node(node: lxml_html.HtmlElement) -> lxml_html.HtmlElement | None:
        anchor = anchor_by_id.get(id(node))
        if anchor is not None:
            return anchor
        current = node
        while current is not None:
            sibling = current.getprevious()
            while sibling is not None:
                if not isinstance(sibling.tag, str):
                    sibling = sibling.getprevious()
                    continue
                text = sibling.text_content().strip()
                if len(text) >= 5:
                    return sibling
                sibling = sibling.getprevious()
            current = current.getparent()
        return None

    def insert_placeholder(video_id: str, node: lxml_html.HtmlElement | None) -> None:
        if video_id in existing_ids:
            return
        placeholder = lxml_html.Element("p")
        placeholder.text = f"YOUTUBE_EMBED:{video_id}"
        insertion = None
        if node is not None:
            anchor = find_anchor_node(node)
            anchor_node = anchor if anchor is not None else node
            insertion = find_insertion_point(
                extracted_tree, anchor_node, raw_dom, anchor_node
            )
        if insertion:
            parent, index = insertion
            parent.insert(index, placeholder)
        else:
            if len(body):
                body.insert(0, placeholder)
            else:
                body.append(placeholder)
        existing_ids.add(video_id)

    for video_id, node in _iter_youtube_elements(raw_dom, base_url):
        insert_placeholder(video_id, node)

    return _safe_html_tostring(extracted_tree, extracted_html)


def replace_youtube_placeholders(markdown: str) -> tuple[str, set[str]]:
    """Replace YouTube placeholders in markdown and return touched ids."""
    replaced_ids: set[str] = set()

    def _replace(match: re.Match[str]) -> str:
        raw_id = match.group(1)
        video_id = raw_id.replace("\\_", "_")
        replaced_ids.add(video_id)
        return f"[YouTube](https://www.youtube.com/watch?v={video_id})"

    updated = re.sub(r"YOUTUBE\\?_EMBED:([A-Za-z0-9_\\-]+)", _replace, markdown)
    return updated, replaced_ids


def build_youtube_anchor_map(
    raw_dom: lxml_html.HtmlElement, base_url: str
) -> list[tuple[str, str]]:
    """Build YouTube anchor tuples from the raw DOM."""
    anchor_by_id: dict[int, lxml_html.HtmlElement] = {}
    last_text_elem: lxml_html.HtmlElement | None = None
    for elem in raw_dom.iter():
        if not isinstance(elem.tag, str):
            continue
        text = elem.text_content().strip()
        if len(text) >= 5:
            last_text_elem = elem
        if last_text_elem is not None:
            anchor_by_id[id(elem)] = last_text_elem

    anchors: list[tuple[str, str]] = []
    candidates = list(_iter_youtube_elements(raw_dom, base_url))
    for video_id, node in candidates:
        anchor = anchor_by_id.get(id(node))
        if anchor is None:
            continue
        anchor_text = anchor.text_content().strip()
        if not anchor_text:
            continue
        anchors.append((video_id, anchor_text[:200]))

    if anchors or candidates:
        return anchors

    raw_html = _safe_html_tostring(raw_dom, "")
    embed_ids = extract_youtube_video_ids_from_html(raw_html, base_url)
    if not embed_ids:
        return anchors
    soup = BeautifulSoup(raw_html, "html.parser")
    paragraphs = [p for p in soup.find_all("p") if p.get_text(strip=True)]
    if not paragraphs:
        return anchors
    paragraph_map = sorted(
        ((p.sourceline or 0, p) for p in paragraphs), key=lambda item: item[0]
    )
    for video_id in embed_ids:
        idx = raw_html.find(video_id)
        if idx == -1:
            continue
        line_no = raw_html.count("\n", 0, idx) + 1
        candidate = None
        for line, paragraph in paragraph_map:
            if line <= line_no:
                candidate = paragraph
            else:
                break
        if candidate is None:
            continue
        anchor_text = candidate.get_text(strip=True)
        if anchor_text:
            anchors.append((video_id, anchor_text[:200]))
    return anchors


def insert_youtube_after_anchors(
    markdown: str, anchors: list[tuple[str, str]]
) -> tuple[str, set[str]]:
    """Insert YouTube links after detected anchor text blocks."""
    inserted: set[str] = set()
    if not anchors:
        return markdown, inserted

    lines = markdown.splitlines()

    def _normalize_text(value: str) -> str:
        return re.sub(r"\s+", " ", value).strip().lower()

    for video_id, anchor_text in anchors:
        link = f"[YouTube](https://www.youtube.com/watch?v={video_id})"
        if link in markdown:
            inserted.add(video_id)
            continue
        anchor_words = anchor_text.split()
        anchor_key = _normalize_text(" ".join(anchor_words[:8])) if anchor_words else ""
        if not anchor_key:
            continue
        for idx, line in enumerate(lines):
            line_norm = _normalize_text(line)
            if anchor_key in line_norm:
                lines.insert(idx + 1, "")
                lines.insert(idx + 2, link)
                inserted.add(video_id)
                break

    return "\n".join(lines), inserted
