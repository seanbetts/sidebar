"""Local parsing utilities for the web-save skill."""
from __future__ import annotations

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


def fetch_html(url: str, *, timeout: int = 30) -> tuple[str, str]:
    """Fetch raw HTML and return (html, final_url)."""
    headers = {"User-Agent": USER_AGENT}
    response = requests.get(url, headers=headers, timeout=timeout)
    response.raise_for_status()
    return response.text, str(response.url)


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
    engine = get_rule_engine()
    pre_rules = engine.match_rules(final_url, html, phase="pre")
    render_mode, wait_for, render_timeout = resolve_rendering_settings(pre_rules)
    used_js_rendering = False
    if render_mode == "force":
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
    markdown = html_to_markdown(article_html)
    if not markdown:
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
    if image_url and "![" not in markdown:
        resolved_image = urljoin(source_url, image_url)
        markdown = f"![{title}]({resolved_image})\n\n{markdown}"

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
