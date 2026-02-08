"""blog.google-specific extraction helpers for web-save parsing."""

from __future__ import annotations

from copy import deepcopy

from lxml import html as lxml_html


def extract_blog_google_body_html(raw_html: str) -> str | None:
    """Extract ordered blog.google article modules from rendered HTML."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")

    container = None
    for selector in (
        ".uni-content.uni-blog-article-container",
        ".article-container__content",
        '[data-component="uni-article-body"]',
    ):
        nodes = tree.cssselect(selector)
        if nodes:
            container = nodes[0]
            break
    if container is None:
        return None

    ordered_modules: list[lxml_html.HtmlElement] = []
    for child in list(container):
        if not isinstance(child.tag, str):
            continue
        classes = set((child.get("class") or "").split())
        if "module--text__article" in classes:
            ordered_modules.append(deepcopy(child))
            continue
        if child.tag in {"uni-pull-quote", "uni-image-full-width"}:
            ordered_modules.append(deepcopy(child))

    if not ordered_modules:
        return None

    root = lxml_html.Element("html")
    body = lxml_html.Element("body")
    root.append(body)
    for module in ordered_modules:
        body.append(module)
    return lxml_html.tostring(root, encoding="unicode", method="html")
