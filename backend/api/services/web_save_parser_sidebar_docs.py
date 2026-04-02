"""docs.trysidebar.ai-specific extraction helpers for web-save parsing."""

from __future__ import annotations

from copy import deepcopy

from lxml import html as lxml_html


def _strip_heading_permalink_controls(node: lxml_html.HtmlElement) -> None:
    """Remove Mintlify's hidden permalink controls from heading nodes."""
    heading_xpath = (
        "self::h1 | self::h2 | self::h3 | self::h4 | self::h5 | self::h6 | "
        ".//*[self::h1 or self::h2 or self::h3 or self::h4 or self::h5 or self::h6]"
    )
    for heading in node.xpath(heading_xpath):
        for child in list(heading):
            if not isinstance(child.tag, str):
                continue
            child_class = child.get("class") or ""
            if child.tag == "div" and "absolute" in child_class.split():
                tail_text = child.tail or ""
                previous_sibling = child.getprevious()
                if previous_sibling is not None:
                    previous_sibling.tail = (previous_sibling.tail or "") + tail_text
                else:
                    heading.text = (heading.text or "") + tail_text
                heading.remove(child)


def extract_sidebar_docs_body_html(raw_html: str) -> str | None:
    """Extract the main docs article while preserving heading and hero image order."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")

    content_nodes = tree.cssselect("#content")
    if not content_nodes:
        return None
    content = content_nodes[0]

    h1_nodes = tree.cssselect("#header h1") or content.cssselect("h1")
    if not h1_nodes:
        return None
    heading = deepcopy(h1_nodes[0])

    root = lxml_html.Element("html")
    body = lxml_html.Element("body")
    root.append(body)
    _strip_heading_permalink_controls(heading)
    body.append(heading)

    for child in content.iterchildren():
        if isinstance(child.tag, str):
            child_id = (child.get("id") or "").strip().lower()
            if child.tag == "h1" or child_id == "page-title":
                continue
        cloned_child = deepcopy(child)
        if isinstance(cloned_child.tag, str):
            _strip_heading_permalink_controls(cloned_child)
        body.append(cloned_child)

    return lxml_html.tostring(root, encoding="unicode", method="html")
