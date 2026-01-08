"""Cleanup helpers for web-save parsing."""

from __future__ import annotations

import html
import json
import re
from typing import Any
from urllib.parse import parse_qs, unquote, urljoin, urlparse

from bs4 import BeautifulSoup
from lxml import html as lxml_html

from api.services.web_save_parser_youtube import (
    YOUTUBE_ID_PATTERN,
    extract_youtube_video_id,
)


def _canonical_image_url(url: str) -> str:
    if not url:
        return url
    unquoted = unquote(url)
    http_index = unquoted.rfind("http://")
    https_index = unquoted.rfind("https://")
    idx = max(http_index, https_index)
    if idx > 0:
        unquoted = unquoted[idx:]
    parsed = urlparse(unquoted)
    if parsed.scheme and parsed.netloc:
        host = parsed.netloc.lower().strip(".")
        if host.startswith("www."):
            host = host[4:]
        path = parsed.path or ""
        if host.endswith(".wp.com") and path.startswith("/"):
            parts = path.lstrip("/").split("/", 1)
            if len(parts) == 2 and "." in parts[0]:
                return f"https://{parts[0]}/{parts[1]}"
        return parsed._replace(query="", fragment="").geturl()
    http_index = unquoted.rfind("http://")
    https_index = unquoted.rfind("https://")
    idx = max(http_index, https_index)
    if idx != -1:
        return unquoted[idx:]
    return unquoted


def _unwrap_proxy_image_url(url: str) -> str:
    if not url:
        return url
    parsed = urlparse(url)
    host = parsed.netloc.lower().strip(".")
    if host.endswith("substackcdn.com") and "/image/fetch/" in parsed.path:
        canonical = _canonical_image_url(url)
        if canonical and canonical != url:
            return canonical
    return url


def dedupe_markdown_images(markdown: str) -> str:
    """Remove duplicate image references while preserving order."""
    seen: set[str] = set()

    image_url_pattern = r"!\[[^\]]*]\(([^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\)"
    linked_pattern = rf"\[{image_url_pattern}\]\([^)]+\)"
    combined_pattern = re.compile(rf"{linked_pattern}|{image_url_pattern}")

    output: list[str] = []
    last_end = 0
    for match in combined_pattern.finditer(markdown):
        output.append(markdown[last_end : match.start()])
        url = match.group(1) or match.group(2)
        key = _canonical_image_url(url) if url else ""
        if key and key not in seen:
            seen.add(key)
            output.append(match.group(0))
        last_end = match.end()
    output.append(markdown[last_end:])

    deduped = "".join(output)
    deduped = re.sub(r"(?<!!)\[\s*]\([^)]+\)", "", deduped)
    deduped = re.sub(r"\[!\]\([^)]+\)", "", deduped)
    deduped = re.sub(r"\)\s*(\!\[)", r")\n\n\1", deduped)
    deduped = re.sub(r"\)\s*(\[!\[)", r")\n\n\1", deduped)
    return deduped.strip()


def wrap_gallery_blocks(markdown: str) -> str:
    """Wrap consecutive gallery images into a single HTML gallery block."""
    image_line = re.compile(
        r"^!\[[^\]]*]\(([^)\s]+)(?:\s+(?:\"([^\"]*)\"|\'([^\']*)\'))?\)\s*$"
    )
    lines = markdown.splitlines()
    output: list[str] = []
    index = 0
    while index < len(lines):
        if not lines[index].strip():
            output.append(lines[index])
            index += 1
            continue
        matches: list[tuple[str, str | None]] = []
        consumed = 0
        while index + consumed < len(lines):
            line = lines[index + consumed]
            if not line.strip():
                consumed += 1
                continue
            match = image_line.match(line.strip())
            if not match:
                break
            url = match.group(1)
            title = match.group(2) or match.group(3)
            matches.append((url, title))
            consumed += 1
        if matches:
            caption = matches[-1][1]
            if caption and len(matches) >= 2:
                escaped_caption = html.escape(caption, quote=True)
                output.append(
                    f'<figure class="image-gallery" data-caption="{escaped_caption}">'
                )
                output.append('  <div class="image-gallery-grid">')
                for url, _title in matches:
                    output.append(f'    <img src="{html.escape(url, quote=True)}" />')
                output.append("  </div>")
                output.append("</figure>")
                index += consumed
                continue
        output.append(lines[index])
        index += 1
    return "\n".join(output).strip()


def simplify_linked_images(markdown: str) -> str:
    """Unwrap linked images that point to the same target URL."""
    image_link_pattern = re.compile(
        r"\[!\[[^\]]*]\(([^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\)\]\(([^)\s]+)\)"
    )

    def _replace(match: re.Match[str]) -> str:
        image_url = match.group(1)
        link_url = match.group(2)
        if _canonical_image_url(image_url) == _canonical_image_url(link_url):
            return f"![]({image_url})"
        return match.group(0)

    return image_link_pattern.sub(_replace, markdown)


def cleanup_verge_markdown(markdown: str) -> str:
    """Remove Verge gallery chrome text from markdown."""
    if not markdown:
        return markdown
    output: list[str] = []
    caption_pattern = re.compile(r"^\*{2}\d+/\d+\*{2}\s*Image:\s*.+$")
    skip_follow_block = False
    for line in markdown.splitlines():
        stripped = line.strip()
        lowered = stripped.lower()
        if "follow topics and authors" in lowered:
            skip_follow_block = True
            continue
        if skip_follow_block:
            if not stripped:
                continue
            if stripped.startswith(("* ", "- ")):
                continue
            skip_follow_block = False
        if not stripped:
            output.append(line)
            continue
        if caption_pattern.match(stripped):
            continue
        if lowered in {"previousnext", "previous", "next"}:
            continue
        output.append(line)
    return "\n".join(output).strip()


def cleanup_gizmodo_markdown(markdown: str) -> str:
    """Remove Gizmodo inline promo blockquotes."""
    if not markdown:
        return markdown
    output: list[str] = []
    blockquote_lines: list[str] = []

    def _flush_blockquote() -> None:
        if not blockquote_lines:
            return
        content = " ".join(
            line.lstrip("> ").strip() for line in blockquote_lines if line.strip()
        ).lower()
        if "want more io9 news" in content:
            return
        output.extend(blockquote_lines)

    for line in markdown.splitlines():
        if line.lstrip().startswith(">"):
            blockquote_lines.append(line)
            continue
        if blockquote_lines:
            _flush_blockquote()
            blockquote_lines = []
        output.append(line)

    _flush_blockquote()
    return "\n".join(output).strip()


def cleanup_youtube_markdown(markdown: str, source_url: str) -> str:
    """Reduce YouTube page markdown to a single embed link."""
    if not markdown:
        return markdown
    video_id = extract_youtube_video_id(source_url)
    if video_id:
        return f"[YouTube](https://www.youtube.com/watch?v={video_id})"
    match = YOUTUBE_ID_PATTERN.search(markdown)
    if match:
        return f"[YouTube](https://www.youtube.com/watch?v={match.group(1)})"
    return markdown


def cleanup_openai_markdown(markdown: str) -> str:
    """Remove OpenAI credits/team blocks from markdown."""
    if not markdown:
        return markdown

    link_text_cleanup = re.compile(r"\(opens in a new window\)", re.IGNORECASE)
    labels = {
        "research",
        "product",
        "contributors",
        "leadership",
        "special thanks",
        "safety, integrity, product policy, i2, user ops",
        "legal",
        "communications",
        "marketing, design, & creative",
        "global affairs",
        "strategic finance",
        "api",
    }
    output: list[str] = []
    skipping = False
    footer_mode = False
    kept_footer_meta = 0

    for line in markdown.splitlines():
        stripped = line.strip()
        lowered = stripped.lower()

        if footer_mode:
            if kept_footer_meta < 2 and (
                lowered.startswith("built by openai")
                or lowered.startswith("published ")
            ):
                output.append(stripped)
                kept_footer_meta += 1
            continue

        if stripped in {"Loading…", "Loading...", "Share"}:
            continue

        if stripped.startswith("[Research]") and "openai.com" in stripped:
            continue
        if stripped.startswith("[") and "](" in stripped:
            matches = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", stripped)
            if len(matches) >= 2:
                labels = {label.strip().lower() for label, _ in matches}
                hrefs = [href for _, href in matches]
                if labels.issubset({"research", "product", "release"}) and all(
                    "openai.com" in href for href in hrefs
                ):
                    continue

        if stripped.startswith("## "):
            if lowered in {"## author", "## keep reading"}:
                footer_mode = True
                continue
            if lowered == "## sora 2":
                footer_mode = True
                continue

        if not skipping:
            for label in labels:
                if (lowered == label or lowered.startswith(label)) and (
                    len(stripped) > len(label) + 2
                    or "," in stripped
                    or lowered == label
                ):
                    skipping = True
                    break
            if skipping:
                continue

        if skipping:
            if lowered.startswith("built by openai") or lowered.startswith(
                "published "
            ):
                skipping = False
                output.append(line)
            continue

        if link_text_cleanup.search(stripped):
            output.append(link_text_cleanup.sub("", stripped).strip())
            continue

        output.append(line)

    return "\n".join(output).strip()


def extract_openai_body_html(raw_html: str) -> str | None:
    """Extract the main OpenAI article content from rendered HTML."""
    if not raw_html:
        return None
    try:
        tree = lxml_html.fromstring(raw_html)
    except ValueError:
        tree = lxml_html.fragment_fromstring(raw_html, create_parent="div")
    target = None
    for selector in ("article", "main"):
        nodes = tree.cssselect(selector)
        if nodes:
            target = nodes[0]
            break
    if target is None:
        return None
    for node in target.cssselect("nav, header, footer"):
        parent = node.getparent()
        if parent is not None:
            parent.remove(node)
    return lxml_html.tostring(target, encoding="unicode", method="html")


def extract_body_html(html_text: str) -> str:
    """Extract inner body HTML from a full document."""
    soup = BeautifulSoup(html_text, "html.parser")
    if soup.body:
        return "".join(str(child) for child in soup.body.contents)
    return html_text


def normalize_image_sources(html_text: str, base_url: str) -> str:
    """Normalize image sources for markdown conversion."""
    soup = BeautifulSoup(html_text, "html.parser")
    for img in soup.find_all("img"):
        src = img.get("src")
        if not src:
            for attr in (
                "data-src",
                "data-original",
                "data-lazy-src",
                "data-url",
                "data-srcset",
                "srcset",
            ):
                value = img.get(attr)
                if not value:
                    continue
                if "srcset" in attr:
                    value = value.split(",")[0].split()[0]
                src = value
                break
        if src:
            resolved = urljoin(base_url, src)
            img["src"] = _unwrap_proxy_image_url(resolved)
    return str(soup)


def normalize_link_sources(html_text: str, base_url: str) -> str:
    """Normalize hrefs to absolute URLs for markdown conversion."""
    soup = BeautifulSoup(html_text, "html.parser")
    for link in soup.find_all("a"):
        href = link.get("href")
        if not href:
            continue
        parsed = urlparse(href)
        if parsed.scheme in {"mailto", "tel"}:
            continue
        if href.startswith("#"):
            continue
        link["href"] = urljoin(base_url, href)
    return str(soup)


def _normalize_image_identity(url: str) -> tuple[str, str]:
    canonical = _canonical_image_url(url)
    parsed = urlparse(canonical)
    host = parsed.netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    return host, parsed.path.rstrip("/")


def _srcset_contains(srcset: str, candidate: str) -> bool:
    return any(candidate in part.strip() for part in srcset.split(","))


def prepend_hero_image(html_text: str, image_url: str, title: str) -> str:
    """Ensure hero image is present near the top of the extracted HTML."""
    if not image_url:
        return html_text
    canonical_image = _canonical_image_url(image_url)
    if image_url in html_text or canonical_image in unquote(html_text):
        return html_text
    soup = BeautifulSoup(html_text, "html.parser")
    candidate_identity = _normalize_image_identity(canonical_image)
    for img in soup.find_all("img"):
        src = img.get("src") or ""
        if src and _normalize_image_identity(src) == candidate_identity:
            return html_text
        srcset = img.get("srcset")
        if srcset and _srcset_contains(srcset, image_url):
            return html_text
    hero = soup.new_tag("img", src=image_url, alt=title or "Hero image")
    target = soup.body or soup
    if target.contents:
        target.insert(0, hero)
    else:
        target.append(hero)
    return str(soup)


def normalize_image_captions(html_text: str) -> str:
    """Attach figure captions to image title attributes for Markdown rendering."""
    soup = BeautifulSoup(html_text, "html.parser")

    for figure in soup.find_all("figure"):
        figcaption = figure.find("figcaption")
        if not figcaption:
            continue
        caption = figcaption.get_text(" ", strip=True)
        if not caption:
            figcaption.decompose()
            continue
        img = figure.find("img")
        if img and not img.get("title"):
            img["title"] = caption
        figcaption.decompose()

    for node in soup.find_all(attrs={"data-attrs": True}):
        data_attrs = node.get("data-attrs")
        if not data_attrs:
            continue
        try:
            payload = json.loads(data_attrs)
        except json.JSONDecodeError:
            continue
        gallery = payload.get("gallery") if isinstance(payload, dict) else None
        if not isinstance(gallery, dict):
            continue
        caption = gallery.get("caption")
        if not caption:
            continue
        images = gallery.get("images")
        gallery_sources: list[str] = []
        if isinstance(images, list):
            for item in images:
                if not isinstance(item, dict):
                    continue
                src = item.get("src")
                if src:
                    gallery_sources.append(src)
        if gallery_sources:
            matched_imgs: list[Any] = []
            used: set[int] = set()
            all_imgs = soup.find_all("img")
            for src in gallery_sources:
                target_key = _canonical_image_url(src)
                found = None
                for img in all_imgs:
                    if id(img) in used:
                        continue
                    candidate = img.get("src")
                    if not candidate:
                        continue
                    if _canonical_image_url(candidate) == target_key:
                        found = img
                        break
                if found is None:
                    break
                used.add(id(found))
                matched_imgs.append(found)
            if matched_imgs:
                for img in matched_imgs[:-1]:
                    if img.get("title") == caption:
                        del img["title"]
                img = matched_imgs[-1]
                existing = img.get("title")
                if existing is None or existing == caption:
                    img["title"] = caption
                continue
        imgs = node.find_all("img")
        if not imgs:
            continue
        for img in imgs[:-1]:
            if img.get("title") == caption:
                del img["title"]
        img = imgs[-1]
        existing = img.get("title")
        if existing is None or existing == caption:
            img["title"] = caption

    return str(soup)


def is_paywalled(html_text: str, domain: str | None = None) -> bool:
    """Detect likely paywall markers in HTML."""
    tokens = (
        "paywall",
        "meteredcontent",
        "gateway-content",
        "subscribe to read",
        "subscription required",
        "subscriber-only",
        "sign in to continue",
        "account required",
        "piano",
        "tinypass",
        "paywall-wrapper",
    )
    paywalled_domains = (
        "nytimes.com",
        "wsj.com",
        "ft.com",
        "economist.com",
        "bloomberg.com",
    )
    if domain and domain.endswith(paywalled_domains):
        return True
    lowered = html_text.lower()
    return any(token in lowered for token in tokens)


def filter_non_content_images(html_text: str, *, domain: str | None = None) -> str:
    """Remove likely decorative images from article content."""
    soup = BeautifulSoup(html_text, "html.parser")
    decorative_tokens = [
        "logo",
        "avatar",
        "icon",
        "shield",
        "sprite",
        "badge",
        "gravatar",
        "emoji",
        "favicon",
        "profile",
        "author",
        "social",
        "share",
        "shields.io",
        "private-user-images.githubusercontent.com",
    ]
    if domain and domain.endswith("github.com"):
        decorative_tokens = [
            token
            for token in decorative_tokens
            if token != "private-user-images.githubusercontent.com"
        ]

    def parse_dimension(value: str | None) -> int | None:
        if not value:
            return None
        digits = re.sub(r"\D", "", value)
        return int(digits) if digits.isdigit() else None

    def is_thumbnail_url(url: str) -> bool:
        parsed = urlparse(url)
        if not parsed.query:
            return False
        params = parse_qs(parsed.query)
        width = params.get("w", [None])[0]
        height = params.get("h", [None])[0]
        crop = params.get("crop", [None])[0]
        resize = params.get("resize", [None])[0]
        width_val = parse_dimension(str(width)) if width else None
        height_val = parse_dimension(str(height)) if height else None
        if resize and "," in resize:
            try:
                resize_w, resize_h = resize.split(",", 1)
                width_val = width_val or parse_dimension(resize_w)
                height_val = height_val or parse_dimension(resize_h)
            except ValueError:
                pass
        return bool(
            width_val
            and height_val
            and width_val <= 320
            and height_val <= 200
            and (crop in {"1", "true"} or resize)
        )

    for img in soup.find_all("img"):
        if img.find_parent("figure"):
            continue
        if img.get("role") == "presentation" or img.get("aria-hidden") == "true":
            img.decompose()
            continue
        if any(
            parent.name in {"nav", "header", "footer", "aside"}
            for parent in img.parents
            if getattr(parent, "name", None)
        ):
            img.decompose()
            continue
        attr_text = " ".join(
            value
            for value in (
                " ".join(img.get("class", [])),
                img.get("id", ""),
                img.get("alt", ""),
                img.get("src", ""),
            )
            if value
        ).lower()
        if any(token in attr_text for token in decorative_tokens):
            img.decompose()
            continue
        src = img.get("src") or ""
        if src and is_thumbnail_url(src):
            img.decompose()
            continue
        width = parse_dimension(img.get("width"))
        height = parse_dimension(img.get("height"))
        if width is not None and height is not None and width <= 48 and height <= 48:
            img.decompose()
            continue

    return str(soup)


def _median(values: list[int]) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    mid = len(values) // 2
    if len(values) % 2 == 1:
        return float(values[mid])
    return (values[mid - 1] + values[mid]) / 2.0


def polish_article_html(html_text: str) -> str:
    """Apply safe post-extraction cleanups to article HTML."""
    soup = BeautifulSoup(html_text, "html.parser")

    marks = soup.find_all("mark")
    if marks:
        lengths = [len(mark.get_text(strip=True)) for mark in marks]
        if len(marks) >= 5 and _median(lengths) <= 30:
            for mark in marks:
                mark.unwrap()

    for link in soup.find_all("a"):
        text = link.get_text(strip=True)
        if text:
            continue
        children = list(link.children)
        if not children:
            continue
        has_only_svg = True
        for child in children:
            if getattr(child, "name", None) == "svg":
                continue
            if getattr(child, "strip", None) is not None and not child.strip():
                continue
            has_only_svg = False
            break
        if not has_only_svg:
            continue
        for ancestor in link.parents:
            tag = getattr(ancestor, "name", None)
            if tag in {"nav", "header", "footer", "aside"}:
                link.decompose()
                break
            classes = (
                " ".join(ancestor.get("class", []))
                if getattr(ancestor, "get", None)
                else ""
            )
            ident = ancestor.get("id", "") if getattr(ancestor, "get", None) else ""
            marker = f"{classes} {ident}".lower()
            if any(
                token in marker
                for token in ("nav", "header", "footer", "aside", "menu", "social")
            ):
                link.decompose()
                break

    return str(soup)
