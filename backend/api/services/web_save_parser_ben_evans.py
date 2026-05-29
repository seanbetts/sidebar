"""Benedict Evans blog extraction helpers."""

from __future__ import annotations

from copy import deepcopy

from lxml import html as lxml_html


def extract_ben_evans_body_html(
    raw_html: str,
) -> tuple[str, dict[str, str | None]] | None:
    """Extract Squarespace article content from ben-evans.com in source order."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")

    article_nodes = tree.cssselect("article")
    heading_nodes = tree.cssselect("article h1")
    layout_nodes = tree.cssselect("article .sqs-layout")
    if not article_nodes or not heading_nodes or not layout_nodes:
        return None

    root = lxml_html.Element("html")
    body = lxml_html.Element("body")
    root.append(body)
    body.append(deepcopy(heading_nodes[0]))

    for block in layout_nodes[0].cssselect(".sqs-block"):
        block_classes = set((block.get("class") or "").split())
        if "sqs-block-html" in block_classes:
            appended_any = False
            for content in block.cssselect(".sqs-html-content"):
                for child in content.iterchildren():
                    body.append(deepcopy(child))
                    appended_any = True
            if not appended_any:
                for paragraph in block.cssselect("p"):
                    body.append(deepcopy(paragraph))
            continue
        if "sqs-block-image" in block_classes:
            figure = _extract_image_figure(block)
            if figure is not None:
                body.append(figure)

    if len(body) <= 1:
        return None

    return (
        lxml_html.tostring(root, encoding="unicode", method="html"),
        {"image": None},
    )


def _extract_image_figure(node: lxml_html.HtmlElement) -> lxml_html.HtmlElement | None:
    """Return a simplified figure for a Squarespace image block."""
    image = _select_image_node(node)
    if image is None:
        return None

    figure = lxml_html.Element("figure")
    normalized = lxml_html.Element("img")
    normalized.set(
        "src",
        image.get("src") or image.get("data-src") or image.get("data-image") or "",
    )
    alt = (image.get("alt") or "").strip()
    if alt:
        normalized.set("alt", alt)
    figure.append(normalized)

    caption = _extract_caption(node)
    if caption is not None:
        figure.append(caption)
    return figure


def _select_image_node(node: lxml_html.HtmlElement) -> lxml_html.HtmlElement | None:
    """Return the first concrete image in a Squarespace image block."""
    for image in node.cssselect("img"):
        src = image.get("src") or image.get("data-src") or image.get("data-image")
        if src:
            return image
    return None


def _extract_caption(node: lxml_html.HtmlElement) -> lxml_html.HtmlElement | None:
    """Return a normalized figcaption when the block has visible caption content."""
    caption_nodes = node.cssselect(
        ".image-caption p, .image-caption span, .image-caption a, "
        ".image-caption-wrapper p, .image-caption-wrapper span, "
        ".image-caption-wrapper a"
    )
    if not caption_nodes:
        return None

    figcaption = lxml_html.Element("figcaption")
    for caption_node in caption_nodes:
        text = " ".join(caption_node.text_content().split())
        if not text:
            continue
        if caption_node.tag == "a" and caption_node.get("href"):
            link = lxml_html.Element("a")
            link.set("href", caption_node.get("href"))
            link.text = text
            figcaption.append(link)
            continue
        if len(figcaption):
            if figcaption[-1].tail:
                figcaption[-1].tail += f" {text}"
            else:
                figcaption[-1].tail = f" {text}"
        else:
            figcaption.text = f"{figcaption.text or ''}{text}".strip()
    if figcaption.text or len(figcaption):
        return figcaption
    return None
