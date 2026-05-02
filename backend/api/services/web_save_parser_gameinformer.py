"""Game Informer-specific extraction helpers."""

from __future__ import annotations

from copy import deepcopy

from lxml import html as lxml_html


def extract_gameinformer_body_html(raw_html: str) -> str | None:
    """Extract the main Game Informer article while preserving title and images."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")

    body_nodes = tree.cssselect(".field--name-body")
    heading_nodes = tree.cssselect("h1")
    if not body_nodes or not heading_nodes:
        return None

    article_body = body_nodes[0]
    heading = deepcopy(heading_nodes[0])
    hero_image = _extract_hero_image(tree)

    root = lxml_html.Element("html")
    body = lxml_html.Element("body")
    root.append(body)
    body.append(heading)
    if hero_image is not None:
        body.append(hero_image)

    for child in article_body.iterchildren():
        body.append(deepcopy(child))

    return lxml_html.tostring(root, encoding="unicode", method="html")


def _extract_hero_image(tree: lxml_html.HtmlElement) -> lxml_html.HtmlElement | None:
    """Return a cloned hero image element when present."""
    hero_nodes = tree.cssselect(".field--name-field-image img")
    if not hero_nodes:
        return None
    return deepcopy(hero_nodes[0])
