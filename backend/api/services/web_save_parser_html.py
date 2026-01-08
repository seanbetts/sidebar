"""Shared HTML parsing helpers for web-save."""

from __future__ import annotations

from lxml import html as lxml_html


def _safe_html_tree(html_text: str) -> lxml_html.HtmlElement:
    """Parse HTML into a safe lxml tree."""
    try:
        tree = lxml_html.fromstring(html_text)
    except (TypeError, ValueError):
        return lxml_html.fragment_fromstring(html_text, create_parent="div")
    if not isinstance(tree.tag, str):
        return lxml_html.fragment_fromstring(html_text, create_parent="div")
    return tree


def _safe_html_tostring(tree: lxml_html.HtmlElement, fallback_html: str) -> str:
    """Serialize an lxml tree, falling back to a safe parse on failure."""
    try:
        return lxml_html.tostring(tree, encoding="unicode")
    except (TypeError, ValueError):
        safe_tree = _safe_html_tree(fallback_html)
        return lxml_html.tostring(safe_tree, encoding="unicode")
