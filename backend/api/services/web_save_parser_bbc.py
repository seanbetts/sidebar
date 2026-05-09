"""BBC News-specific extraction helpers."""

from __future__ import annotations

import json
from copy import deepcopy

from lxml import html as lxml_html

_DROP_COMPONENTS = {
    "byline-block",
    "links-block",
    "embed-block",
    "tag-list-block",
}


def extract_bbc_body_html(raw_html: str) -> tuple[str, dict[str, str | None]] | None:
    """Extract BBC article content in article order while dropping recirculation."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")

    article = tree.cssselect("article")
    if not article:
        return None

    root = lxml_html.Element("html")
    body = lxml_html.Element("body")
    root.append(body)

    title = _extract_text(tree.cssselect("article h1"))
    hero_added = False

    for child in article[0].iterchildren():
        component = child.get("data-component")
        if not component or component in _DROP_COMPONENTS:
            continue

        if component == "headline-block":
            heading_nodes = child.cssselect("h1")
            if heading_nodes:
                body.append(deepcopy(heading_nodes[0]))
            continue

        if component == "image-block":
            figure = _extract_image_figure(child)
            if figure is not None:
                body.append(figure)
                hero_added = True
            continue

        if component == "text-block":
            appended = False
            content_nodes = child.xpath("./p|./ul|./ol|./blockquote")
            if isinstance(content_nodes, list):
                for node in content_nodes:
                    if not isinstance(node, lxml_html.HtmlElement):
                        continue
                    body.append(deepcopy(node))
                    appended = True
            if not appended:
                paragraphs = child.cssselect("p")
                for paragraph in paragraphs:
                    body.append(deepcopy(paragraph))
            continue

        if component == "subheadline-block":
            subheadline = _extract_subheadline(child)
            if subheadline is not None:
                body.append(subheadline)
            continue

    if len(body) == 0:
        return None

    metadata = _extract_bbc_metadata(tree)
    if title:
        metadata["title"] = title
    if hero_added and body.cssselect("img"):
        metadata["image"] = None

    return lxml_html.tostring(root, encoding="unicode", method="html"), metadata


def _extract_image_figure(node: lxml_html.HtmlElement) -> lxml_html.HtmlElement | None:
    """Return a cleaned figure from a BBC image block."""
    images = node.cssselect("img")
    selected = next(
        (
            image
            for image in images
            if "hide-when-no-script" not in (image.get("class") or "")
            and image.get("src")
            and "grey-placeholder" not in image.get("src", "")
        ),
        None,
    )
    if selected is None:
        return None

    figure = lxml_html.Element("figure")
    image = deepcopy(selected)
    figure.append(image)

    figcaption = node.cssselect("figcaption")
    if figcaption:
        figure.append(deepcopy(figcaption[0]))

    return figure


def _extract_subheadline(node: lxml_html.HtmlElement) -> lxml_html.HtmlElement | None:
    """Normalize BBC subheadline blocks into h2 tags."""
    text = " ".join(node.text_content().split())
    if not text:
        return None
    heading = lxml_html.Element("h2")
    heading.text = text
    return heading


def _extract_text(nodes: list[lxml_html.HtmlElement]) -> str | None:
    """Return normalized text from the first node."""
    if not nodes:
        return None
    text = " ".join(nodes[0].text_content().split())
    return text or None


def _extract_bbc_metadata(tree: lxml_html.HtmlElement) -> dict[str, str | None]:
    """Pull stable metadata from BBC News JSON-LD when present."""
    for script in tree.xpath('//script[@type="application/ld+json"]'):
        raw_text = (script.text or "").strip()
        if not raw_text:
            continue
        try:
            payload = json.loads(raw_text)
        except json.JSONDecodeError:
            continue
        candidates = payload if isinstance(payload, list) else [payload]
        for candidate in candidates:
            if not isinstance(candidate, dict):
                continue
            if candidate.get("@type") not in {
                "NewsArticle",
                "ReportageNewsArticle",
            }:
                continue
            author = _extract_author(candidate.get("author"))
            image = candidate.get("thumbnailUrl")
            if not image and isinstance(candidate.get("image"), dict):
                image = candidate["image"].get("url")
            return {
                "title": candidate.get("headline"),
                "author": author,
                "image": image if isinstance(image, str) else None,
            }
    return {}


def _extract_author(author_value: object) -> str | None:
    """Return a normalized BBC author string from JSON-LD author payloads."""
    if isinstance(author_value, dict):
        name = author_value.get("name")
        return name if isinstance(name, str) else None
    if isinstance(author_value, list):
        names = []
        for entry in author_value:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            if isinstance(name, str):
                names.append(name)
        return ", ".join(names) if names else None
    return None
