"""docs.trysidebar.ai-specific extraction helpers for web-save parsing."""

from __future__ import annotations

from copy import deepcopy

from lxml import html as lxml_html


def _element_text_key(node: lxml_html.HtmlElement) -> str:
    """Return a normalized text key for duplicate detection."""
    return "".join(node.itertext()).strip().lower()


def extract_sidebar_docs_body_html(raw_html: str) -> str | None:
    """Extract the main docs article while preserving heading and hero image order."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")

    article = None
    for selector in (
        "main",
        "article",
        '[class*="content"]',
    ):
        nodes = tree.cssselect(selector)
        for node in nodes:
            if node.cssselect("h1"):
                article = node
                break
        if article is not None:
            break
    if article is None:
        return None

    h1_nodes = article.cssselect("h1")
    if not h1_nodes:
        return None
    heading = deepcopy(h1_nodes[0])

    hero_image = None
    for img in article.cssselect("img"):
        alt = (img.get("alt") or "").strip().lower()
        src = (img.get("src") or "").strip()
        if not src:
            continue
        if "sidebar app overview" in alt:
            hero_image = deepcopy(img)
            break
    if hero_image is None:
        article_images = article.cssselect("img")
        if article_images:
            hero_image = deepcopy(article_images[0])

    root = lxml_html.Element("html")
    body = lxml_html.Element("body")
    root.append(body)
    body.append(heading)
    if hero_image is not None:
        body.append(hero_image)

    appended_keys: set[str] = set()
    heading_key = _element_text_key(heading)
    if heading_key:
        appended_keys.add(heading_key)
    if hero_image is not None:
        hero_src = (hero_image.get("src") or "").strip()
        if hero_src:
            appended_keys.add(hero_src)

    for child in article.iterchildren():
        if not isinstance(child.tag, str):
            continue
        if child.tag == "h1":
            continue
        if child.tag == "img":
            src = (child.get("src") or "").strip()
            if src and src in appended_keys:
                continue
        text_key = _element_text_key(child)
        if text_key and text_key in appended_keys:
            continue
        body.append(deepcopy(child))
        if text_key:
            appended_keys.add(text_key)

    return lxml_html.tostring(root, encoding="unicode", method="html")
