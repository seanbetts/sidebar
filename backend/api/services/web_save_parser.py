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
    priority: int
    trigger: dict
    remove: list[str]
    include: list[str]
    selector_overrides: dict
    metadata: dict
    actions: list[dict]


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
    overrides = extract_metadata_overrides(article_html, post_rules)
    if overrides:
        metadata.update(overrides)
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
    return value.lower().strip(".")


def _host_variants(host: str) -> dict:
    cleaned = _normalize_host(host)
    no_www = cleaned[4:] if cleaned.startswith("www.") else cleaned
    with_www = cleaned if cleaned.startswith("www.") else f"www.{no_www}"
    parts = no_www.split(".")
    etld_plus_one = no_www
    if len(parts) >= 2:
        etld_plus_one = ".".join(parts[-2:])
    return {
        "host_raw": cleaned,
        "host_nw": no_www,
        "host_with_www": with_www,
        "etld_plus_one": etld_plus_one,
    }


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
                        priority=item.get("priority", 0),
                        trigger=item.get("trigger", {}),
                        remove=item.get("remove", []) or [],
                        include=item.get("include", []) or [],
                        selector_overrides=item.get("selector_overrides", {}) or {},
                        metadata=item.get("metadata", {}) or {},
                        actions=item.get("actions", []) or [],
                    )
                )
        rules.sort(key=lambda rule: rule.priority, reverse=True)
        return cls(rules)

    def match_rules(self, url: str, html: str, phase: str) -> list[Rule]:
        host_info = _host_variants(urlparse(url).netloc)
        tree = lxml_html.fromstring(html)
        matches: list[Rule] = []

        for rule in self._rules:
            if rule.phase not in {phase, "both"}:
                continue
            if self._matches_trigger(rule.trigger, host_info, tree):
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

            for action in rule.actions or []:
                self._apply_action(tree, action)

        return lxml_html.tostring(tree, encoding="unicode")

    def _matches_trigger(self, trigger: dict, host_info: dict, tree: lxml_html.HtmlElement) -> bool:
        if not trigger:
            return False

        mode = trigger.get("mode", "all")
        host_rule = trigger.get("host") or {}
        dom_rule = trigger.get("dom") or {}

        host_match = False
        if host_rule:
            if "equals" in host_rule and _normalize_host(host_rule["equals"]) == host_info["host_nw"]:
                host_match = True
            if "equals_www" in host_rule and _normalize_host(host_rule["equals_www"]) == host_info["host_with_www"]:
                host_match = True
            if "ends_with" in host_rule:
                target = _normalize_host(host_rule["ends_with"])
                if host_info["host_nw"].endswith(target) or host_info["etld_plus_one"].endswith(target):
                    host_match = True
            if "etld_plus_one" in host_rule and _normalize_host(host_rule["etld_plus_one"]) == host_info["etld_plus_one"]:
                host_match = True

        dom_match = False
        dom_any = dom_rule.get("any") or []
        dom_all = dom_rule.get("all") or []
        text_any = dom_rule.get("any_text_contains") or []

        if dom_any:
            dom_match = any(tree.cssselect(selector) for selector in dom_any)
        if dom_all:
            dom_match = all(tree.cssselect(selector) for selector in dom_all)
        if text_any:
            text = (tree.text_content() or "").lower()
            dom_match = any(token.lower() in text for token in text_any)

        if mode == "any":
            return host_match or dom_match
        if host_rule and dom_rule:
            return host_match and dom_match
        return host_match or dom_match

    def _apply_action(self, tree: lxml_html.HtmlElement, action: dict) -> None:
        op = action.get("op")
        selector = action.get("selector")
        if not op or not selector:
            return

        nodes = tree.cssselect(selector)
        if not nodes:
            return

        if op == "retag":
            tag = action.get("tag")
            if not tag:
                return
            for node in nodes:
                node.tag = tag
            return

        if op == "unwrap":
            for node in nodes:
                parent = node.getparent()
                if parent is None:
                    continue
                index = parent.index(node)
                for child in list(node):
                    node.remove(child)
                    parent.insert(index, child)
                    index += 1
                parent.remove(node)
            return

        if op == "remove_container":
            action["op"] = "unwrap"
            self._apply_action(tree, action)
            return

        if op == "wrap":
            wrapper_tag = action.get("wrapper_tag")
            if not wrapper_tag:
                return
            for node in nodes:
                parent = node.getparent()
                if parent is None:
                    continue
                wrapper = lxml_html.Element(wrapper_tag)
                parent.replace(node, wrapper)
                wrapper.append(node)
            return

        if op == "remove_parent":
            for node in nodes:
                parent = node.getparent()
                if parent is None:
                    continue
                grandparent = parent.getparent()
                if grandparent is None:
                    continue
                index = grandparent.index(parent)
                parent.remove(node)
                grandparent.insert(index + 1, node)
                if len(parent) == 0:
                    grandparent.remove(parent)
            return

        if op == "remove_outer_parent":
            for node in nodes:
                parent = node.getparent()
                if parent is None:
                    continue
                grandparent = parent.getparent()
                if grandparent is None:
                    continue
                great = grandparent.getparent()
                if great is None:
                    continue
                index = great.index(grandparent)
                grandparent.remove(node)
                great.insert(index + 1, node)
                if len(grandparent) == 0:
                    great.remove(grandparent)
            return

        if op == "remove_to_parent":
            parent_selector = action.get("parent")
            if not parent_selector:
                return
            for node in nodes:
                current = node.getparent()
                while current is not None:
                    if current.cssselect(parent_selector):
                        break
                    parent = current.getparent()
                    if parent is None:
                        break
                    index = parent.index(current)
                    current.remove(node)
                    parent.insert(index + 1, node)
                    if len(current) == 0:
                        parent.remove(current)
                    current = parent
            return

        if op == "remove_attrs":
            attrs = action.get("attrs") or []
            for node in nodes:
                for attr in attrs:
                    if attr in node.attrib:
                        del node.attrib[attr]
            return

        if op == "set_attr":
            attr = action.get("attr")
            value = action.get("value")
            if not attr or value is None:
                return
            for node in nodes:
                node.set(attr, value)
            return

        if op == "replace_with_text":
            template = action.get("template")
            if not template:
                return
            for node in nodes:
                parent = node.getparent()
                text = template.format(**node.attrib)
                if parent is None:
                    continue
                tail = node.tail or ""
                parent.text = (parent.text or "") + text + tail
                parent.remove(node)
            return

        if op == "move":
            target_selector = action.get("target")
            if not target_selector:
                return
            position = action.get("position", "append")
            target_nodes = tree.cssselect(target_selector)
            if not target_nodes:
                return
            target = target_nodes[0]
            for node in nodes:
                parent = node.getparent()
                if parent is None:
                    continue
                parent.remove(node)
                if position == "prepend":
                    target.insert(0, node)
                elif position == "before":
                    target.addprevious(node)
                elif position == "after":
                    target.addnext(node)
                else:
                    target.append(node)
            return

        if op == "group_siblings":
            wrapper_tag = action.get("wrapper_tag")
            if not wrapper_tag:
                return
            wrapper_class = action.get("class")
            for parent in {node.getparent() for node in nodes if node.getparent() is not None}:
                children = list(parent)
                index = 0
                while index < len(children):
                    child = children[index]
                    if child in nodes:
                        wrapper = lxml_html.Element(wrapper_tag)
                        if wrapper_class:
                            wrapper.set("class", wrapper_class)
                        parent.insert(index, wrapper)
                        while index < len(children) and children[index] in nodes:
                            wrapper.append(children[index])
                            index += 1
                        children = list(parent)
                    else:
                        index += 1
            return

        if op == "reorder":
            method = action.get("method")
            for node in nodes:
                parent = node.getparent()
                if parent is None:
                    continue
                if method == "move_to_top":
                    parent.remove(node)
                    parent.insert(0, node)
                elif method == "move_to_bottom":
                    parent.remove(node)
                    parent.append(node)
            return


def extract_metadata_overrides(html: str, rules: list[Rule]) -> dict:
    """Extract metadata overrides from matched rules."""
    if not rules:
        return {}
    tree = lxml_html.fromstring(html)
    overrides: dict = {}
    for rule in rules:
        meta = rule.metadata or {}
        for key in ("author", "published", "title"):
            if key not in meta:
                continue
            selector = meta[key].get("selector")
            attr = meta[key].get("attr")
            if not selector:
                continue
            nodes = tree.cssselect(selector)
            if not nodes:
                continue
            node = nodes[0]
            value = node.get(attr) if attr else node.text_content()
            if value:
                overrides[key] = value.strip()
    return overrides


@lru_cache(maxsize=1)
def get_rule_engine() -> RuleEngine:
    return RuleEngine.from_rules_dir(RULES_DIR)
