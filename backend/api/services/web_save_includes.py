"""Include reinsertion helpers for web-save parsing."""
from __future__ import annotations

from copy import deepcopy
from difflib import SequenceMatcher
from typing import Optional

from lxml import html as lxml_html


def apply_include_reinsertion(
    extracted_html: str,
    original_dom: lxml_html.HtmlElement,
    include_selectors: list[str],
    removal_rules: list[str],
) -> str:
    """Reinsert forcibly included elements after Readability extraction."""
    extracted_tree = lxml_html.fromstring(extracted_html)
    body = extracted_tree.find(".//body") or extracted_tree

    for selector in include_selectors:
        try:
            for node in original_dom.cssselect(selector):
                cloned = deepcopy(node)
                for removal_selector in removal_rules:
                    for elem in cloned.cssselect(removal_selector):
                        parent = elem.getparent()
                        if parent is not None:
                            parent.remove(elem)
                insertion = find_insertion_point(extracted_tree, cloned, original_dom, node)
                if insertion:
                    parent, index = insertion
                    parent.insert(index, cloned)
                else:
                    body.append(cloned)
        except Exception:
            continue

    return lxml_html.tostring(extracted_tree, encoding="unicode")


def find_insertion_point(
    extracted_tree: lxml_html.HtmlElement,
    cloned_node: lxml_html.HtmlElement,
    original_dom: lxml_html.HtmlElement,
    original_node: lxml_html.HtmlElement,
) -> Optional[tuple[lxml_html.HtmlElement, int]]:
    """Find an insertion point for included elements."""
    node_text = cloned_node.text_content().strip()[:200]
    if node_text:
        best_match = None
        best_ratio = 0.3
        for elem in extracted_tree.iter():
            if elem.tag in {"script", "style", "meta", "link"}:
                continue
            elem_text = elem.text_content().strip()[:200]
            if not elem_text:
                continue
            ratio = SequenceMatcher(None, node_text, elem_text).ratio()
            if ratio > best_ratio:
                best_ratio = ratio
                best_match = elem
        if best_match is not None:
            parent = best_match.getparent()
            if parent is not None:
                return parent, parent.index(best_match) + 1

    position_match = _find_by_position(extracted_tree, original_dom, original_node)
    if position_match:
        return position_match

    headings = extracted_tree.cssselect("h1, h2, h3, h4, h5, h6")
    if headings:
        last_heading = headings[-1]
        parent = last_heading.getparent()
        if parent is not None:
            return parent, parent.index(last_heading) + 1

    return None


def _find_by_position(
    extracted_tree: lxml_html.HtmlElement,
    original_dom: lxml_html.HtmlElement,
    original_node: lxml_html.HtmlElement,
) -> Optional[tuple[lxml_html.HtmlElement, int]]:
    """Match insertion point using original DOM ordering."""
    _ = original_dom
    preceding = original_node.getprevious()
    while preceding is not None:
        preceding_text = preceding.text_content().strip()[:100]
        if preceding_text and len(preceding_text) > 20:
            for elem in extracted_tree.iter():
                elem_text = elem.text_content().strip()[:100]
                if preceding_text in elem_text or elem_text in preceding_text:
                    parent = elem.getparent()
                    if parent is not None:
                        return parent, parent.index(elem) + 1
            break
        preceding = preceding.getprevious()
    return None
