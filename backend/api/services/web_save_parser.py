"""Local parsing utilities for the web-save skill."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import re
import requests
import yaml
from bs4 import BeautifulSoup
from markdownify import markdownify
from readability import Document
from lxml import html as lxml_html

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)

RULES_DIR = Path(__file__).resolve().parents[2] / "skills" / "web-save" / "rules"


@dataclass(frozen=True)
class Rule:
    """Rule definition for web-save parsing."""

    id: str
    phase: str
    trigger: dict
    remove: list[str]
    selector_overrides: dict


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

    engine = get_rule_engine()
    pre_rules = engine.match_rules(final_url, html, phase="pre")
    if pre_rules:
        html = engine.apply_rules(html, pre_rules)

    document = Document(html)
    article_html = document.summary(html_partial=True)
    post_rules = engine.match_rules(final_url, article_html, phase="post")
    if post_rules:
        article_html = engine.apply_rules(article_html, post_rules)
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
def _normalize_host(value: str) -> str:
    return value.lower().lstrip("www.")


class RuleEngine:
    """Minimal rule engine for web-save parsing."""

    def __init__(self, rules: list[Rule]):
        self._rules = rules

    @classmethod
    def from_rules_dir(cls, rules_dir: Path) -> "RuleEngine":
        rules: list[Rule] = []
        for path in sorted(rules_dir.glob("*.yaml")):
            payload = yaml.safe_load(path.read_text()) or []
            for item in payload:
                rules.append(
                    Rule(
                        id=item["id"],
                        phase=item.get("phase", "post"),
                        trigger=item.get("trigger", {}),
                        remove=item.get("remove", []) or [],
                        selector_overrides=item.get("selector_overrides", {}) or {},
                    )
                )
        return cls(rules)

    def match_rules(self, url: str, html: str, phase: str) -> list[Rule]:
        host = _normalize_host(urlparse(url).netloc)
        tree = lxml_html.fromstring(html)
        matches: list[Rule] = []

        for rule in self._rules:
            if rule.phase not in {phase, "both"}:
                continue
            if self._matches_trigger(rule.trigger, host, tree):
                matches.append(rule)
        return matches

    def apply_rules(self, html: str, rules: list[Rule]) -> str:
        tree = lxml_html.fromstring(html)

        for rule in rules:
            overrides = rule.selector_overrides or {}
            selector = overrides.get("article") or overrides.get("wrapper")
            if selector:
                scoped = tree.cssselect(selector)
                if scoped:
                    scoped_root = scoped[0]
                    new_doc = lxml_html.Element("html")
                    body = lxml_html.SubElement(new_doc, "body")
                    body.append(scoped_root)
                    tree = new_doc

            for selector in rule.remove:
                for node in tree.cssselect(selector):
                    parent = node.getparent()
                    if parent is not None:
                        parent.remove(node)

        return lxml_html.tostring(tree, encoding="unicode")

    def _matches_trigger(self, trigger: dict, host: str, tree: lxml_html.HtmlElement) -> bool:
        if not trigger:
            return False

        host_rule = trigger.get("host") or {}
        dom_rule = trigger.get("dom") or {}

        if host_rule:
            if "equals" in host_rule and _normalize_host(host_rule["equals"]) == host:
                return True
            if "ends_with" in host_rule and host.endswith(host_rule["ends_with"]):
                return True

        dom_any = dom_rule.get("any") or []
        if dom_any:
            for selector in dom_any:
                if tree.cssselect(selector):
                    return True

        return False


@lru_cache(maxsize=1)
def get_rule_engine() -> RuleEngine:
    return RuleEngine.from_rules_dir(RULES_DIR)
