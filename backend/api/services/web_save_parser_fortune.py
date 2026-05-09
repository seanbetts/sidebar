"""Fortune-specific article extraction helpers."""

from __future__ import annotations

import json
from copy import deepcopy

from lxml import html as lxml_html


def extract_fortune_body_html(
    raw_html: str,
) -> tuple[str, dict[str, str | None]] | None:
    """Extract the visible Fortune article body and metadata."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")

    article_nodes = tree.cssselect("article.article-content")
    heading_nodes = tree.cssselect("h1")
    if not article_nodes or not heading_nodes:
        return None

    article = article_nodes[0]
    root = lxml_html.Element("html")
    body = lxml_html.Element("body")
    root.append(body)
    body.append(deepcopy(heading_nodes[0]))

    hero_url = _extract_hero_url(tree)
    if hero_url:
        image = lxml_html.Element("img")
        image.set("src", hero_url)
        image.set("alt", _node_text(heading_nodes[0]) or "Fortune article image")
        body.append(image)

    for child in article.iterchildren():
        child_classes = set((child.get("class") or "").split())
        if "paywall-selector" in child_classes:
            continue
        if "paywall" in child_classes:
            _append_fortune_content(body, child)
            continue
        if child.tag == "p":
            body.append(deepcopy(child))

    if not body.cssselect("p"):
        return None

    metadata = _extract_fortune_metadata(tree)
    if hero_url:
        metadata["image"] = None
    return lxml_html.tostring(root, encoding="unicode", method="html"), metadata


def _append_fortune_content(
    body: lxml_html.HtmlElement,
    container: lxml_html.HtmlElement,
) -> None:
    """Append allowed content nodes from the Fortune paywall container."""
    for child in container.iterchildren():
        if child.tag == "p":
            body.append(deepcopy(child))


def _extract_hero_url(tree: lxml_html.HtmlElement) -> str | None:
    """Return the article hero image URL from metadata."""
    image = _meta_content(tree, 'meta[property="og:image"]')
    if image:
        return image
    metadata = _extract_fortune_metadata(tree)
    return metadata.get("image")


def _meta_content(tree: lxml_html.HtmlElement, selector: str) -> str | None:
    """Return the content attribute from the first matching meta tag."""
    nodes = tree.cssselect(selector)
    if not nodes:
        return None
    content = nodes[0].get("content")
    return content.strip() if isinstance(content, str) and content.strip() else None


def _extract_fortune_metadata(tree: lxml_html.HtmlElement) -> dict[str, str | None]:
    """Extract stable title, author, and hero metadata from Fortune JSON-LD."""
    for script in tree.xpath('//script[@type="application/ld+json"]'):
        raw_text = (script.text or "").strip()
        if not raw_text:
            continue
        try:
            payload = json.loads(raw_text)
        except json.JSONDecodeError:
            continue
        if not isinstance(payload, dict):
            continue
        if payload.get("@type") != "NewsArticle":
            continue
        author = _extract_author(payload.get("author"))
        image = payload.get("thumbnailUrl")
        if not isinstance(image, str):
            image = (
                payload.get("image") if isinstance(payload.get("image"), str) else None
            )
        return {
            "title": payload.get("headline")
            if isinstance(payload.get("headline"), str)
            else None,
            "author": author,
            "published": payload.get("datePublished")
            if isinstance(payload.get("datePublished"), str)
            else None,
            "image": image,
        }
    return {}


def _extract_author(author_value: object) -> str | None:
    """Extract a normalized author string from Fortune JSON-LD author payloads."""
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


def _normalize_text(value: str | None) -> str | None:
    """Collapse whitespace for text values."""
    if not value:
        return None
    normalized = " ".join(value.split())
    return normalized or None


def _node_text(node: lxml_html.HtmlElement) -> str | None:
    """Return normalized text content for an lxml node."""
    return _normalize_text(node.text_content())
