"""Shared HTML parsing helpers for web-save."""

from __future__ import annotations

import requests
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


def decode_html_response(response: requests.Response) -> str:
    """Decode HTML bytes while handling incorrect latin-1 defaults."""
    raw = response.content or b""
    if not raw:
        return response.text

    declared = (response.encoding or "").strip().lower()
    # Requests defaults to latin-1 when charset is missing; prefer UTF-8 when valid.
    if not declared or declared in {"iso-8859-1", "latin-1"}:
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            pass

    if declared:
        try:
            return raw.decode(declared)
        except (LookupError, UnicodeDecodeError):
            pass

    fallback = response.text
    if fallback:
        return fallback
    return raw.decode("utf-8", errors="replace")
