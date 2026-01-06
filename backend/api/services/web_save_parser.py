"""Local parsing utilities for the web-save skill."""
from __future__ import annotations

import html
import json
import logging
import re
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any, Optional
from urllib.parse import parse_qs, unquote, urljoin, urlparse

import requests
import yaml
from bs4 import BeautifulSoup
from markdownify import markdownify
from readability import Document
from lxml import html as lxml_html

from api.services.web_save_constants import USER_AGENT
from api.services.web_save_includes import apply_include_reinsertion, find_insertion_point
from api.services.web_save_rendering import (
    has_unrendered_youtube_embed,
    render_html_with_playwright,
    requires_js_rendering,
    resolve_rendering_settings,
)
from api.services.web_save_rules import Rule, RuleEngine, extract_metadata_overrides
from api.services.web_save_tagger import (
    calculate_reading_time,
    compute_word_count,
    extract_tags,
)

logger = logging.getLogger(__name__)

RULES_DIR = Path(__file__).resolve().parents[2] / "skills" / "web-save" / "rules"
PLAYWRIGHT_ALLOWLIST_PATH = RULES_DIR / "playwright_allowlist.yaml"


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


def fetch_html(url: str, *, timeout: int = 30) -> tuple[str, str, bool]:
    """Fetch raw HTML and return (html, final_url, used_js_rendering)."""
    headers = {"User-Agent": USER_AGENT}
    try:
        response = requests.get(url, headers=headers, timeout=timeout)
        response.raise_for_status()
        return response.text, str(response.url), False
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
            return html, final_url, True
        raise


def _discard_frontmatter(
    *,
    source: str,
    domain: str,
    rule: Optional[Rule],
    used_js_rendering: bool,
) -> str:
    reason = "Content discarded by rule"
    if rule:
        reason = f"{reason}: {rule.id}"
    frontmatter_meta = {
        "source": source,
        "domain": domain,
        "discarded": True,
        "discard_reason": reason,
        "rule_id": rule.id if rule else None,
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }
    return build_frontmatter("[Content discarded by parsing rule]", meta=frontmatter_meta)


def _paywall_frontmatter(
    *,
    source: str,
    domain: str,
    used_js_rendering: bool,
) -> str:
    frontmatter_meta = {
        "source": source,
        "domain": domain,
        "discarded": True,
        "paywalled": True,
        "discard_reason": "Paywall detected",
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }
    return build_frontmatter(
        "Unable to save content. This site appears to be behind a paywall.",
        meta=frontmatter_meta,
    )


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
    image = find_meta(["og:image", "twitter:image"], ("property", "name"))

    canonical = None
    canonical_tag = soup.find("link", rel="canonical")
    if canonical_tag and canonical_tag.get("href"):
        canonical = canonical_tag["href"].strip()

    return {
        "title": title,
        "author": author,
        "published": published,
        "canonical": canonical or url,
        "image": image,
    }


def fetch_substack_body_html(url: str, html: str, *, timeout: int = 30) -> Optional[tuple[str, dict]]:
    """Fetch Substack post HTML from the public API when available."""
    if "substack" not in html.lower():
        return None
    parsed = urlparse(url)
    if "/p/" not in parsed.path:
        return None
    slug = parsed.path.split("/p/")[-1].strip("/")
    if not slug:
        return None
    api_url = f"{parsed.scheme}://{parsed.netloc}/api/v1/posts/{slug}"
    response = requests.get(api_url, headers={"User-Agent": USER_AGENT}, timeout=timeout)
    response.raise_for_status()
    data = response.json()
    body_html = data.get("body_html")
    if not body_html:
        return None
    meta = {
        "title": data.get("title"),
        "author": data.get("author") or data.get("author_name"),
        "published": data.get("post_date") or data.get("published_at"),
        "canonical": data.get("canonical_url"),
    }
    return body_html, meta


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


def _canonical_image_url(url: str) -> str:
    if not url:
        return url
    unquoted = unquote(url)
    http_index = unquoted.rfind("http://")
    https_index = unquoted.rfind("https://")
    idx = max(http_index, https_index)
    if idx > 0:
        unquoted = unquoted[idx:]
    parsed = urlparse(unquoted)
    if parsed.scheme and parsed.netloc:
        host = parsed.netloc.lower().strip(".")
        if host.startswith("www."):
            host = host[4:]
        path = parsed.path or ""
        if host.endswith(".wp.com") and path.startswith("/"):
            parts = path.lstrip("/").split("/", 1)
            if len(parts) == 2 and "." in parts[0]:
                return f"https://{parts[0]}/{parts[1]}"
        return parsed._replace(query="", fragment="").geturl()
    http_index = unquoted.rfind("http://")
    https_index = unquoted.rfind("https://")
    idx = max(http_index, https_index)
    if idx != -1:
        return unquoted[idx:]
    return unquoted


def dedupe_markdown_images(markdown: str) -> str:
    """Remove duplicate image references while preserving order."""
    seen: set[str] = set()

    image_url_pattern = r"!\[[^\]]*]\(([^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\)"
    linked_pattern = rf"\[{image_url_pattern}\]\([^)]+\)"
    placeholders: list[str] = []

    def replace_linked(match: re.Match[str]) -> str:
        url = match.group(1)
        key = _canonical_image_url(url)
        if key in seen:
            return ""
        seen.add(key)
        placeholders.append(match.group(0))
        return f"__IMG_PLACEHOLDER_{len(placeholders) - 1}__"

    def replace_plain(match: re.Match[str]) -> str:
        url = match.group(1)
        key = _canonical_image_url(url)
        if key in seen:
            return ""
        seen.add(key)
        return match.group(0)

    deduped = re.sub(linked_pattern, replace_linked, markdown)
    deduped = re.sub(image_url_pattern, replace_plain, deduped)
    deduped = re.sub(r"(?<!!)\[\s*]\([^)]+\)", "", deduped)
    deduped = re.sub(r"\[!\]\([^)]+\)", "", deduped)
    for index, value in enumerate(placeholders):
        deduped = deduped.replace(f"__IMG_PLACEHOLDER_{index}__", value)
    deduped = re.sub(r"\)\s*(\!\[)", r")\n\n\1", deduped)
    deduped = re.sub(r"\)\s*(\[!\[)", r")\n\n\1", deduped)
    return deduped.strip()


def wrap_gallery_blocks(markdown: str) -> str:
    """Wrap consecutive gallery images into a single HTML gallery block."""
    image_line = re.compile(
        r'^!\[[^\]]*]\(([^)\s]+)(?:\s+(?:\"([^\"]*)\"|\'([^\']*)\'))?\)\s*$'
    )
    lines = markdown.splitlines()
    output: list[str] = []
    index = 0
    while index < len(lines):
        if not lines[index].strip():
            output.append(lines[index])
            index += 1
            continue
        matches: list[tuple[str, str | None]] = []
        consumed = 0
        while index + consumed < len(lines):
            line = lines[index + consumed]
            if not line.strip():
                consumed += 1
                continue
            match = image_line.match(line.strip())
            if not match:
                break
            url = match.group(1)
            title = match.group(2) or match.group(3)
            matches.append((url, title))
            consumed += 1
        if matches:
            caption = matches[-1][1]
            if caption and len(matches) >= 2:
                escaped_caption = html.escape(caption, quote=True)
                output.append(f'<figure class="image-gallery" data-caption="{escaped_caption}">')
                output.append('  <div class="image-gallery-grid">')
                for url, _title in matches:
                    output.append(f'    <img src="{html.escape(url, quote=True)}" />')
                output.append('  </div>')
                output.append('</figure>')
                index += consumed
                continue
        output.append(lines[index])
        index += 1
    return "\n".join(output).strip()


def simplify_linked_images(markdown: str) -> str:
    """Unwrap linked images that point to the same target URL."""
    image_link_pattern = re.compile(
        r"\[!\[[^\]]*]\(([^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\)\]\(([^)\s]+)\)"
    )

    def _replace(match: re.Match[str]) -> str:
        image_url = match.group(1)
        link_url = match.group(2)
        if _canonical_image_url(image_url) == _canonical_image_url(link_url):
            return f"![]({image_url})"
        return match.group(0)

    return image_link_pattern.sub(_replace, markdown)


def cleanup_verge_markdown(markdown: str) -> str:
    """Remove Verge gallery chrome text from markdown."""
    if not markdown:
        return markdown
    output: list[str] = []
    caption_pattern = re.compile(r"^\*{2}\d+/\d+\*{2}\s*Image:\s*.+$")
    skip_follow_block = False
    for line in markdown.splitlines():
        stripped = line.strip()
        lowered = stripped.lower()
        if "follow topics and authors" in lowered:
            skip_follow_block = True
            continue
        if skip_follow_block:
            if not stripped:
                continue
            if stripped.startswith(("* ", "- ")):
                continue
            skip_follow_block = False
        if not stripped:
            output.append(line)
            continue
        if caption_pattern.match(stripped):
            continue
        if lowered in {"previousnext", "previous", "next"}:
            continue
        output.append(line)
    return "\n".join(output).strip()


def cleanup_gizmodo_markdown(markdown: str) -> str:
    """Remove Gizmodo inline promo blockquotes."""
    if not markdown:
        return markdown
    output: list[str] = []
    blockquote_lines: list[str] = []

    def _flush_blockquote() -> None:
        if not blockquote_lines:
            return
        content = " ".join(
            line.lstrip("> ").strip() for line in blockquote_lines if line.strip()
        ).lower()
        if "want more io9 news" in content:
            return
        output.extend(blockquote_lines)

    for line in markdown.splitlines():
        if line.lstrip().startswith(">"):
            blockquote_lines.append(line)
            continue
        if blockquote_lines:
            _flush_blockquote()
            blockquote_lines = []
        output.append(line)

    _flush_blockquote()
    return "\n".join(output).strip()


def cleanup_youtube_markdown(markdown: str, source_url: str) -> str:
    """Reduce YouTube page markdown to a single embed link."""
    if not markdown:
        return markdown
    video_id = extract_youtube_video_id(source_url)
    if video_id:
        return f"[YouTube](https://www.youtube.com/watch?v={video_id})"
    match = YOUTUBE_VIDEO_PATTERN.search(markdown)
    if match:
        return f"[YouTube](https://www.youtube.com/watch?v={match.group(1)})"
    return markdown


def extract_body_html(html: str) -> str:
    """Extract inner body HTML from a full document."""
    soup = BeautifulSoup(html, "html.parser")
    if soup.body:
        return "".join(str(child) for child in soup.body.contents)
    return html


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


def normalize_image_sources(html: str, base_url: str) -> str:
    """Normalize image sources for markdown conversion."""
    soup = BeautifulSoup(html, "html.parser")
    for img in soup.find_all("img"):
        src = img.get("src")
        if not src:
            for attr in ("data-src", "data-original", "data-lazy-src", "data-url", "data-srcset", "srcset"):
                value = img.get(attr)
                if not value:
                    continue
                if "srcset" in attr:
                    value = value.split(",")[0].split()[0]
                src = value
                break
        if src:
            img["src"] = urljoin(base_url, src)
    return str(soup)


def normalize_link_sources(html: str, base_url: str) -> str:
    """Normalize hrefs to absolute URLs for markdown conversion."""
    soup = BeautifulSoup(html, "html.parser")
    for link in soup.find_all("a"):
        href = link.get("href")
        if not href:
            continue
        parsed = urlparse(href)
        if parsed.scheme in {"mailto", "tel"}:
            continue
        if href.startswith("#"):
            continue
        link["href"] = urljoin(base_url, href)
    return str(soup)


def _normalize_image_identity(url: str) -> tuple[str, str]:
    canonical = _canonical_image_url(url)
    parsed = urlparse(canonical)
    host = parsed.netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    return host, parsed.path.rstrip("/")


def _srcset_contains(srcset: str, candidate: str) -> bool:
    return any(candidate in part.strip() for part in srcset.split(","))


def prepend_hero_image(html: str, image_url: str, title: str) -> str:
    """Ensure hero image is present near the top of the extracted HTML."""
    if not image_url:
        return html
    canonical_image = _canonical_image_url(image_url)
    if image_url in html or canonical_image in unquote(html):
        return html
    soup = BeautifulSoup(html, "html.parser")
    candidate_identity = _normalize_image_identity(canonical_image)
    for img in soup.find_all("img"):
        src = img.get("src") or ""
        if src:
            if _normalize_image_identity(src) == candidate_identity:
                return html
        srcset = img.get("srcset")
        if srcset and _srcset_contains(srcset, image_url):
            return html
    hero = soup.new_tag("img", src=image_url, alt=title or "Hero image")
    target = soup.body or soup
    if target.contents:
        target.insert(0, hero)
    else:
        target.append(hero)
    return str(soup)


def normalize_image_captions(html: str) -> str:
    """Attach figure captions to image title attributes for Markdown rendering."""
    soup = BeautifulSoup(html, "html.parser")

    for figure in soup.find_all("figure"):
        figcaption = figure.find("figcaption")
        if not figcaption:
            continue
        caption = figcaption.get_text(" ", strip=True)
        if not caption:
            figcaption.decompose()
            continue
        img = figure.find("img")
        if img and not img.get("title"):
            img["title"] = caption
        figcaption.decompose()

    for node in soup.find_all(attrs={"data-attrs": True}):
        data_attrs = node.get("data-attrs")
        if not data_attrs:
            continue
        try:
            payload = json.loads(data_attrs)
        except json.JSONDecodeError:
            continue
        gallery = payload.get("gallery") if isinstance(payload, dict) else None
        if not isinstance(gallery, dict):
            continue
        caption = gallery.get("caption")
        if not caption:
            continue
        images = gallery.get("images")
        gallery_sources: list[str] = []
        if isinstance(images, list):
            for item in images:
                if not isinstance(item, dict):
                    continue
                src = item.get("src")
                if src:
                    gallery_sources.append(src)
        if gallery_sources:
            matched_imgs: list[Any] = []
            used: set[int] = set()
            all_imgs = soup.find_all("img")
            for src in gallery_sources:
                target_key = _canonical_image_url(src)
                found = None
                for img in all_imgs:
                    if id(img) in used:
                        continue
                    candidate = img.get("src")
                    if not candidate:
                        continue
                    if _canonical_image_url(candidate) == target_key:
                        found = img
                        break
                if found is None:
                    break
                used.add(id(found))
                matched_imgs.append(found)
            if matched_imgs:
                for img in matched_imgs[:-1]:
                    if img.get("title") == caption:
                        del img["title"]
                img = matched_imgs[-1]
                existing = img.get("title")
                if existing is None or existing == caption:
                    img["title"] = caption
                continue
        imgs = node.find_all("img")
        if not imgs:
            continue
        for img in imgs[:-1]:
            if img.get("title") == caption:
                del img["title"]
        img = imgs[-1]
        existing = img.get("title")
        if existing is None or existing == caption:
            img["title"] = caption

    return str(soup)


def is_paywalled(html: str, domain: Optional[str] = None) -> bool:
    """Detect likely paywall markers in HTML."""
    tokens = (
        "paywall",
        "meteredcontent",
        "gateway-content",
        "subscribe to read",
        "subscription required",
        "subscriber-only",
        "sign in to continue",
        "account required",
        "piano",
        "tinypass",
        "paywall-wrapper",
    )
    paywalled_domains = (
        "nytimes.com",
        "wsj.com",
        "ft.com",
        "economist.com",
        "bloomberg.com",
    )
    if domain and domain.endswith(paywalled_domains):
        return True
    lowered = html.lower()
    return any(token in lowered for token in tokens)


def filter_non_content_images(html: str, *, domain: Optional[str] = None) -> str:
    """Remove likely decorative images from article content."""
    soup = BeautifulSoup(html, "html.parser")
    decorative_tokens = [
        "logo",
        "avatar",
        "icon",
        "shield",
        "sprite",
        "badge",
        "gravatar",
        "emoji",
        "favicon",
        "profile",
        "author",
        "social",
        "share",
        "shields.io",
        "private-user-images.githubusercontent.com",
    ]
    if domain and domain.endswith("github.com"):
        decorative_tokens = [
            token for token in decorative_tokens if token != "private-user-images.githubusercontent.com"
        ]

    def parse_dimension(value: Optional[str]) -> Optional[int]:
        if not value:
            return None
        digits = re.sub(r"\D", "", value)
        return int(digits) if digits.isdigit() else None

    def is_thumbnail_url(url: str) -> bool:
        parsed = urlparse(url)
        if not parsed.query:
            return False
        params = parse_qs(parsed.query)
        width = params.get("w", [None])[0]
        height = params.get("h", [None])[0]
        crop = params.get("crop", [None])[0]
        resize = params.get("resize", [None])[0]
        width_val = parse_dimension(str(width)) if width else None
        height_val = parse_dimension(str(height)) if height else None
        if resize and "," in resize:
            try:
                resize_w, resize_h = resize.split(",", 1)
                width_val = width_val or parse_dimension(resize_w)
                height_val = height_val or parse_dimension(resize_h)
            except ValueError:
                pass
        if width_val and height_val and width_val <= 320 and height_val <= 200:
            if crop in {"1", "true"} or resize:
                return True
        return False

    for img in soup.find_all("img"):
        if img.find_parent("figure"):
            continue
        if img.get("role") == "presentation" or img.get("aria-hidden") == "true":
            img.decompose()
            continue
        if any(
            parent.name in {"nav", "header", "footer", "aside"}
            for parent in img.parents
            if getattr(parent, "name", None)
        ):
            img.decompose()
            continue
        attr_text = " ".join(
            value
            for value in (
                " ".join(img.get("class", [])),
                img.get("id", ""),
                img.get("alt", ""),
                img.get("src", ""),
            )
            if value
        ).lower()
        if any(token in attr_text for token in decorative_tokens):
            img.decompose()
            continue
        src = img.get("src") or ""
        if src and is_thumbnail_url(src):
            img.decompose()
            continue
        width = parse_dimension(img.get("width"))
        height = parse_dimension(img.get("height"))
        if width is not None and height is not None and width <= 48 and height <= 48:
            img.decompose()
            continue

    return str(soup)


def _median(values: list[int]) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    mid = len(values) // 2
    if len(values) % 2 == 1:
        return float(values[mid])
    return (values[mid - 1] + values[mid]) / 2.0


def polish_article_html(html: str) -> str:
    """Apply safe post-extraction cleanups to article HTML."""
    soup = BeautifulSoup(html, "html.parser")

    marks = soup.find_all("mark")
    if marks:
        lengths = [len(mark.get_text(strip=True)) for mark in marks]
        if len(marks) >= 5 and _median(lengths) <= 30:
            for mark in marks:
                mark.unwrap()

    for link in soup.find_all("a"):
        text = link.get_text(strip=True)
        if text:
            continue
        children = list(link.children)
        if not children:
            continue
        has_only_svg = True
        for child in children:
            if getattr(child, "name", None) == "svg":
                continue
            if getattr(child, "strip", None) is not None and not child.strip():
                continue
            has_only_svg = False
            break
        if not has_only_svg:
            continue
        for ancestor in link.parents:
            tag = getattr(ancestor, "name", None)
            if tag in {"nav", "header", "footer", "aside"}:
                link.decompose()
                break
            classes = " ".join(ancestor.get("class", [])) if getattr(ancestor, "get", None) else ""
            ident = ancestor.get("id", "") if getattr(ancestor, "get", None) else ""
            marker = f"{classes} {ident}".lower()
            if any(token in marker for token in ("nav", "header", "footer", "aside", "menu", "social")):
                link.decompose()
                break

    return str(soup)


YOUTUBE_ID_PATTERN = re.compile(
    r"(?:youtube\.com/(?:watch\?v=|embed/)|youtu\.be/)([A-Za-z0-9_-]+)"
)
YOUTUBE_EMBED_PATTERN = re.compile(
    r"(?:youtube(?:-nocookie)?\.com/(?:embed/|v/))([A-Za-z0-9_-]+)"
)
YOUTUBE_RAW_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{11}$")
YOUTUBE_EMBED_TAGS = {"iframe", "lite-youtube", "amp-youtube", "youtube-player", "yt-embed"}
YOUTUBE_ID_ATTRS = {
    "data-youtube-id",
    "data-youtubeid",
    "data-yt-id",
    "data-ytid",
    "data-video-id",
    "data-videoid",
    "data-video",
    "data-videoid",
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
JSONLD_MEDIA_PATTERN = re.compile(r"\[(?:Media|Video):\s*(https?://[^\]]+)\]", re.IGNORECASE)
JSONLD_YOUTUBE_PATTERN = re.compile(
    r"https?://(?:www\.)?(?:youtube\.com/watch\?v=|youtu\.be/)[A-Za-z0-9_-]+",
    re.IGNORECASE,
)


def extract_youtube_video_id(url: str) -> str | None:
    match = YOUTUBE_ID_PATTERN.search(url)
    return match.group(1) if match else None


def extract_youtube_embed_id(url: str) -> str | None:
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
    for attr, value in elem.attrib.items():
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
        re.search(r"\b(ad|ads|advert|advertisement|sponsor|sponsored|promo|promoted)\b", value)
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
    if "youtube" in classes and ("player" in classes or "embed" in classes):
        return True
    return False


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


def extract_youtube_anchors_from_jsonld(html: str) -> tuple[list[tuple[str, str]], set[str]]:
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


def _safe_html_tree(html_text: str) -> lxml_html.HtmlElement:
    try:
        tree = lxml_html.fromstring(html_text)
    except (TypeError, ValueError):
        return lxml_html.fragment_fromstring(html_text, create_parent="div")
    if not isinstance(tree.tag, str):
        return lxml_html.fragment_fromstring(html_text, create_parent="div")
    return tree


def _safe_html_tostring(tree: lxml_html.HtmlElement, fallback_html: str) -> str:
    try:
        return lxml_html.tostring(tree, encoding="unicode")
    except (TypeError, ValueError):
        safe_tree = _safe_html_tree(fallback_html)
        return lxml_html.tostring(safe_tree, encoding="unicode")


def extract_youtube_video_ids_from_html(html: str, base_url: str) -> list[str]:
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
    """Extract YouTube embed URLs from iframe elements while skipping ad/cookie embeds."""
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


def insert_youtube_placeholders(
    extracted_html: str, raw_dom: lxml_html.HtmlElement, base_url: str
) -> str:
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
            insertion = find_insertion_point(extracted_tree, anchor_node, raw_dom, anchor_node)
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


def build_frontmatter(markdown_text: str, *, meta: dict) -> str:
    """Build YAML frontmatter + markdown output."""
    payload = {key: value for key, value in meta.items() if value is not None}
    frontmatter = yaml.safe_dump(
        payload, sort_keys=False, allow_unicode=False
    ).strip()
    return f"---\n{frontmatter}\n---\n\n{markdown_text.strip()}\n"


def parse_url_local(url: str, *, timeout: int = 30) -> ParsedPage:
    """Parse a URL locally into Markdown with frontmatter."""
    start_time = time.monotonic()
    normalized = ensure_url(url)
    logger.info("web-save parse start url=%s", normalized)
    html, final_url, used_js_rendering = fetch_html(normalized, timeout=timeout)
    logger.info(
        "web-save fetched url=%s final_url=%s used_js=%s html_len=%s",
        normalized,
        final_url,
        used_js_rendering,
        len(html),
    )
    initial_html = html
    initial_url = final_url
    engine = get_rule_engine()
    pre_rules = engine.match_rules(final_url, html, phase="pre")
    if pre_rules:
        logger.info(
            "web-save pre rules url=%s ids=%s",
            final_url,
            [rule.id for rule in pre_rules],
        )
    render_mode, wait_for, render_timeout = resolve_rendering_settings(pre_rules)
    if used_js_rendering:
        pass
    elif render_mode == "force":
        html, final_url = render_html_with_playwright(
            final_url, timeout=render_timeout, wait_for=wait_for
        )
        used_js_rendering = True
    elif render_mode == "auto" and requires_js_rendering(html):
        unrendered_embed = has_unrendered_youtube_embed(html)
        allow_render = is_playwright_allowed(final_url) or unrendered_embed
        if allow_render:
            try:
                if unrendered_embed:
                    html, final_url = render_html_with_playwright(
                        final_url,
                        timeout=min(render_timeout, 15000),
                        wait_for=wait_for,
                        wait_until="domcontentloaded",
                    )
                else:
                    html, final_url = render_html_with_playwright(
                        final_url, timeout=render_timeout, wait_for=wait_for
                    )
                used_js_rendering = True
            except RuntimeError:
                pass

    if html != initial_html or final_url != initial_url:
        pre_rules = engine.match_rules(final_url, html, phase="pre")
        if pre_rules:
            logger.info(
                "web-save pre rules (post-render) url=%s ids=%s",
                final_url,
                [rule.id for rule in pre_rules],
            )
    logger.info(
        "web-save rendering url=%s mode=%s used_js=%s wait_for=%s timeout_ms=%s",
        final_url,
        render_mode,
        used_js_rendering,
        wait_for,
        render_timeout,
    )

    raw_html_original = html
    metadata = extract_metadata(html, final_url)
    if pre_rules:
        html = engine.apply_rules(html, pre_rules)
    discard_rule = next((rule for rule in pre_rules if rule.discard), None)
    if discard_rule:
        content = _discard_frontmatter(
            source=metadata.get("canonical") or final_url,
            domain=urlparse(final_url).netloc,
            rule=discard_rule,
            used_js_rendering=used_js_rendering,
        )
        return ParsedPage(
            title=metadata.get("title") or urlparse(final_url).netloc,
            content=content,
            source=metadata.get("canonical") or final_url,
            published_at=None,
        )

    html, pre_youtube_ids = replace_youtube_iframes_with_placeholders(
        html, metadata.get("canonical") or final_url
    )
    raw_dom = _safe_html_tree(html)
    raw_dom_original = _safe_html_tree(raw_html_original)
    pre_dom = _safe_html_tree(html)

    document = Document(html)
    substack_payload = None
    try:
        substack_payload = fetch_substack_body_html(final_url, html, timeout=timeout)
    except requests.RequestException:
        substack_payload = None
    if substack_payload:
        article_html, substack_meta = substack_payload
        metadata.update({key: value for key, value in substack_meta.items() if value})
    else:
        article_html = document.summary(html_partial=True)
    logger.info(
        "web-save readability url=%s article_len=%s",
        final_url,
        len(article_html),
    )
    post_rules = engine.match_rules(final_url, article_html, phase="post")
    if post_rules:
        logger.info(
            "web-save post rules url=%s ids=%s",
            final_url,
            [rule.id for rule in post_rules],
        )
        post_tree = _safe_html_tree(article_html)
        post_tree = engine.apply_rules_tree(post_tree, post_rules)
        article_html = _safe_html_tostring(post_tree, article_html)
    discard_rule = next((rule for rule in post_rules if rule.discard), None)
    if discard_rule:
        content = _discard_frontmatter(
            source=metadata.get("canonical") or final_url,
            domain=urlparse(final_url).netloc,
            rule=discard_rule,
            used_js_rendering=used_js_rendering,
        )
        return ParsedPage(
            title=metadata.get("title") or urlparse(final_url).netloc,
            content=content,
            source=metadata.get("canonical") or final_url,
            published_at=None,
        )
    overrides = extract_metadata_overrides(article_html, post_rules)
    if overrides:
        metadata.update(overrides)
    include_selectors = [
        selector for rule in pre_rules + post_rules for selector in rule.include
    ]
    removal_selectors = [selector for rule in post_rules for selector in rule.remove]
    reinsert_dom = raw_dom
    if any(rule.selector_overrides for rule in pre_rules):
        reinsert_dom = pre_dom
        removal_selectors = [
            selector for rule in pre_rules + post_rules for selector in rule.remove
        ]
    if include_selectors:
        article_html = apply_include_reinsertion(
            article_html,
            reinsert_dom,
            include_selectors,
            removal_selectors,
        )
        logger.info(
            "web-save include reinsertion url=%s selectors=%s removals=%s",
            final_url,
            len(include_selectors),
            len(removal_selectors),
        )
    domain = urlparse(final_url).netloc
    before_img_count = len(BeautifulSoup(article_html, "html.parser").find_all("img"))
    article_html = filter_non_content_images(article_html, domain=domain)
    after_img_count = len(BeautifulSoup(article_html, "html.parser").find_all("img"))
    logger.info(
        "web-save images url=%s before=%s after=%s",
        final_url,
        before_img_count,
        after_img_count,
    )
    article_html = polish_article_html(article_html)
    article_html = normalize_image_sources(
        article_html, metadata.get("canonical") or final_url
    )
    article_html = normalize_link_sources(
        article_html, metadata.get("canonical") or final_url
    )
    article_html = normalize_image_captions(article_html)
    article_html = insert_youtube_placeholders(
        article_html, raw_dom_original, metadata.get("canonical") or final_url
    )
    title = (
        metadata.get("title")
        or document.short_title()
        or document.title()
        or urlparse(final_url).netloc
    )
    source_url = metadata.get("canonical") or final_url
    image_url = metadata.get("image")
    if image_url:
        resolved_image = urljoin(source_url, image_url)
        article_html = prepend_hero_image(article_html, resolved_image, title)
    markdown = html_to_markdown(article_html)
    if domain.endswith("theverge.com"):
        markdown = simplify_linked_images(markdown)
        markdown = cleanup_verge_markdown(markdown)
    if domain.endswith("gizmodo.com"):
        markdown = cleanup_gizmodo_markdown(markdown)
    if domain.endswith("youtube.com"):
        markdown = cleanup_youtube_markdown(markdown, source_url)
    logger.info("web-save markdown url=%s len=%s", final_url, len(markdown))
    markdown, embedded_ids = replace_youtube_placeholders(markdown)
    embedded_ids = embedded_ids.union(pre_youtube_ids)
    jsonld_anchors, jsonld_ids = extract_youtube_anchors_from_jsonld(raw_html_original)
    anchors = _merge_youtube_anchors(
        jsonld_anchors,
        build_youtube_anchor_map(raw_dom_original, metadata.get("canonical") or final_url),
    )
    if jsonld_ids:
        logger.info(
            "web-save youtube jsonld url=%s ids=%s",
            final_url,
            sorted(jsonld_ids),
        )
    if anchors:
        markdown, anchored_ids = insert_youtube_after_anchors(markdown, anchors)
        embedded_ids = embedded_ids.union(anchored_ids)
        logger.info(
            "web-save youtube anchors url=%s anchors=%s inserted=%s",
            final_url,
            len(anchors),
            len(anchored_ids),
        )
    if not markdown:
        domain = urlparse(final_url).netloc
        if is_paywalled(html, domain) or is_paywalled(article_html, domain):
            content = _paywall_frontmatter(
                source=metadata.get("canonical") or final_url,
                domain=domain,
                used_js_rendering=used_js_rendering,
            )
            title = (
                metadata.get("title")
                or document.short_title()
                or document.title()
                or urlparse(final_url).netloc
            )
            return ParsedPage(
                title=title,
                content=content,
                source=metadata.get("canonical") or final_url,
                published_at=None,
            )
        raise ValueError("No readable content extracted")

    published_at = parse_datetime(metadata.get("published"))
    word_count = compute_word_count(markdown)
    domain = urlparse(final_url).netloc
    tags = extract_tags(markdown, domain, title)
    source_url = metadata.get("canonical") or final_url

    embeds = extract_youtube_embed_urls_from_dom(
        raw_dom_original, metadata.get("canonical") or final_url
    )
    if not embeds and not embedded_ids:
        if jsonld_ids:
            embeds = [
                f"https://www.youtube.com/watch?v={video_id}"
                for video_id in sorted(jsonld_ids)
            ]
        else:
            if not domain.endswith("theverge.com"):
                script_ids = extract_youtube_video_ids_from_html(
                    raw_html_original, metadata.get("canonical") or final_url
                )
                if script_ids:
                    embeds = [f"https://www.youtube.com/watch?v={script_ids[0]}"]
    if embeds:
        existing = markdown
        lines = []
        for embed_url in embeds:
            video_id = extract_youtube_video_id(embed_url)
            if video_id and video_id in embedded_ids:
                continue
            if embed_url in existing:
                continue
            lines.append(f"[YouTube]({embed_url})")
        if lines:
            cookie_marker = "content isn't visible due to your cookie preferences"
            if cookie_marker in markdown:
                split_lines = markdown.splitlines()
                for idx, line in enumerate(split_lines):
                    if cookie_marker in line.lower():
                        insertion_index = idx + 1
                        for offset, link in enumerate(lines):
                            split_lines.insert(insertion_index + offset, link)
                        markdown = "\n".join(split_lines)
                        break
                else:
                    markdown = f"{markdown}\n\n" + "\n".join(lines)
            else:
                markdown = f"{markdown}\n\n" + "\n".join(lines)
        logger.info(
            "web-save youtube fallback url=%s added=%s",
            final_url,
            len(lines),
        )

    markdown = dedupe_markdown_images(markdown)
    markdown = wrap_gallery_blocks(markdown)
    gallery_blocks = markdown.count('class="image-gallery"')
    logger.info(
        "web-save postprocess url=%s markdown_len=%s galleries=%s elapsed_ms=%s",
        final_url,
        len(markdown),
        gallery_blocks,
        int((time.monotonic() - start_time) * 1000),
    )

    frontmatter_meta = {
        "source": metadata.get("canonical") or final_url,
        "title": title,
        "author": metadata.get("author"),
        "published_date": published_at.isoformat() if published_at else None,
        "domain": domain,
        "word_count": word_count,
        "reading_time": calculate_reading_time(word_count),
        "tags": tags,
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }

    content = build_frontmatter(markdown, meta=frontmatter_meta)

    return ParsedPage(
        title=title,
        content=content,
        source=metadata.get("canonical") or final_url,
        published_at=published_at,
    )
@lru_cache(maxsize=1)
def get_rule_engine() -> RuleEngine:
    return RuleEngine.from_rules_dir(RULES_DIR)


@lru_cache(maxsize=1)
def get_playwright_allowlist() -> set[str]:
    if not PLAYWRIGHT_ALLOWLIST_PATH.exists():
        return set()
    payload = yaml.safe_load(PLAYWRIGHT_ALLOWLIST_PATH.read_text()) or []
    if isinstance(payload, list):
        return {str(item).strip().lower() for item in payload if str(item).strip()}
    return set()


def is_playwright_allowed(url: str) -> bool:
    host = urlparse(url).netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    if not host:
        return False
    allowlist = get_playwright_allowlist()
    return any(host == domain or host.endswith(f".{domain}") for domain in allowlist)
