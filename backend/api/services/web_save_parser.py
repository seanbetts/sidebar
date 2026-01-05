"""Local parsing utilities for the web-save skill."""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Optional
from urllib.parse import urljoin, urlparse

import requests
import yaml
from bs4 import BeautifulSoup
from markdownify import markdownify
from readability import Document
from lxml import html as lxml_html

from api.services.web_save_constants import USER_AGENT
from api.services.web_save_includes import apply_include_reinsertion
from api.services.web_save_rendering import (
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

RULES_DIR = Path(__file__).resolve().parents[2] / "skills" / "web-save" / "rules"


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


def dedupe_markdown_images(markdown: str) -> str:
    """Remove duplicate image references while preserving order."""
    seen = set()

    def replace(match: re.Match[str]) -> str:
        url = match.group(1)
        if url in seen:
            return ""
        seen.add(url)
        return match.group(0)

    deduped = re.sub(r"!\[[^\]]*]\(([^)]+)\)", replace, markdown)
    return deduped.strip()


def extract_body_html(html: str) -> str:
    """Extract inner body HTML from a full document."""
    soup = BeautifulSoup(html, "html.parser")
    if soup.body:
        return "".join(str(child) for child in soup.body.contents)
    return html


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
        width = parse_dimension(img.get("width"))
        height = parse_dimension(img.get("height"))
        if width is not None and height is not None and width <= 48 and height <= 48:
            img.decompose()
            continue

    return str(soup)


def extract_youtube_embeds(html: str, base_url: str) -> list[str]:
    """Extract YouTube embed URLs from HTML."""
    soup = BeautifulSoup(html, "html.parser")
    embeds: list[str] = []
    for iframe in soup.find_all("iframe"):
        src = iframe.get("src")
        if not src:
            continue
        normalized = urljoin(base_url, src)
        if "youtube.com" in normalized or "youtu.be" in normalized:
            if "youtube.com/embed/" in normalized:
                video_id = normalized.split("youtube.com/embed/")[-1].split("?")[0]
                normalized = f"https://www.youtube.com/watch?v={video_id}"
            embeds.append(normalized)
    # De-duplicate while preserving order
    seen = set()
    ordered: list[str] = []
    for url in embeds:
        if url in seen:
            continue
        seen.add(url)
        ordered.append(url)
    return ordered


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
    html, final_url, used_js_rendering = fetch_html(normalized, timeout=timeout)
    engine = get_rule_engine()
    pre_rules = engine.match_rules(final_url, html, phase="pre")
    render_mode, wait_for, render_timeout = resolve_rendering_settings(pre_rules)
    if used_js_rendering:
        pass
    elif render_mode == "force":
        html, final_url = render_html_with_playwright(
            final_url, timeout=render_timeout, wait_for=wait_for
        )
        used_js_rendering = True
    elif render_mode == "auto" and requires_js_rendering(html):
        try:
            html, final_url = render_html_with_playwright(
                final_url, timeout=render_timeout, wait_for=wait_for
            )
            used_js_rendering = True
        except RuntimeError:
            pass

    metadata = extract_metadata(html, final_url)
    pre_rules = engine.match_rules(final_url, html, phase="pre")
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

    original_dom = lxml_html.fromstring(html)
    include_selectors = [selector for rule in pre_rules for selector in rule.include]
    removal_selectors = [selector for rule in pre_rules for selector in rule.remove]

    document = Document(html)
    use_raw_html = any(
        rule.selector_overrides.get("article") or rule.selector_overrides.get("wrapper")
        for rule in pre_rules
    )
    substack_payload = None
    try:
        substack_payload = fetch_substack_body_html(final_url, html, timeout=timeout)
    except requests.RequestException:
        substack_payload = None
    if substack_payload:
        article_html, substack_meta = substack_payload
        metadata.update({key: value for key, value in substack_meta.items() if value})
    elif use_raw_html:
        article_html = extract_body_html(html)
    else:
        article_html = document.summary(html_partial=True)
    if include_selectors:
        article_html = apply_include_reinsertion(
            article_html,
            original_dom,
            include_selectors,
            removal_selectors,
        )
    post_rules = engine.match_rules(final_url, article_html, phase="post")
    if post_rules:
        article_html = engine.apply_rules(article_html, post_rules)
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
    domain = urlparse(final_url).netloc
    article_html = filter_non_content_images(article_html, domain=domain)
    article_html = normalize_image_sources(
        article_html, metadata.get("canonical") or final_url
    )
    embeds = extract_youtube_embeds(article_html, metadata.get("canonical") or final_url)
    markdown = html_to_markdown(article_html)
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

    title = (
        metadata.get("title")
        or document.short_title()
        or document.title()
        or urlparse(final_url).netloc
    )
    published_at = parse_datetime(metadata.get("published"))
    word_count = compute_word_count(markdown)
    domain = urlparse(final_url).netloc
    tags = extract_tags(markdown, domain, title)
    source_url = metadata.get("canonical") or final_url
    image_url = metadata.get("image")
    if image_url:
        resolved_image = urljoin(source_url, image_url)
        if resolved_image not in markdown:
            markdown = f"![{title}]({resolved_image})\n\n{markdown}"

    if embeds:
        existing = markdown
        lines = []
        for embed_url in embeds:
            if embed_url in existing:
                continue
            lines.append(f"[YouTube]({embed_url})")
        if lines:
            markdown = f"{markdown}\n\n" + "\n".join(lines)

    markdown = dedupe_markdown_images(markdown)

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
