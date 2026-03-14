"""Substack-specific markdown cleanup helpers for web-save parsing."""

from __future__ import annotations

import json
import re
from urllib.parse import urljoin

from bs4 import BeautifulSoup

from api.services.web_save_parser_cleanup import _canonical_image_url

_LINKED_IMAGE_PATTERN = re.compile(
    (
        r"\[\s*!\[(?P<alt>[^\]]*)\]\((?P<image>[^)\s]+)"
        r"(?:\s+(?:\"[^\"]*\"|'[^']*'))?\)"
        r"(?:\s*<svg\b[^>]*>.*?</svg>\s*)*"
        r"\s*]\((?P<link>https?://[^)\s]+)\)"
    ),
    flags=re.IGNORECASE | re.DOTALL,
)
_INLINE_IMAGE_LINK_PATTERN = re.compile(
    r"\[\s*!\[\]\([^)]+\)\s*(?P<label>[^\]]+)]\((?P<link>https?://[^)\s]+)\)",
    flags=re.IGNORECASE | re.DOTALL,
)
_FOOTNOTE_REF_PATTERN = re.compile(r"\[(?P<num>\d+)]\(#footnote-(?P=num)\)")
_FOOTNOTE_ANCHOR_PATTERN = re.compile(
    r"^\[(?P<num>\d+)]\(#footnote-anchor-(?P=num)\)\s*$"
)
_EMPTY_HEADING_PATTERN = re.compile(r"^#{1,6}$")
_EMPTY_IMAGE_PATTERN = re.compile(
    r"!\[\]\((?P<image>[^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\)"
)
_SUBSTACK_VIDEO_ATTR_MEDIA_ID = re.compile(
    r'"mediauploadid":"(?P<id>[^"]+)"', re.IGNORECASE
)
_SUBSTACK_VIDEO_POSTER = re.compile(r'poster="(?P<poster>[^"]+)"', re.IGNORECASE)


def _normalize_footnotes(markdown: str) -> str:
    """Normalize Substack footnote links to markdown footnotes."""
    normalized = _FOOTNOTE_REF_PATTERN.sub(r"[^\g<num>]", markdown)
    lines = normalized.splitlines()
    output: list[str] = []
    index = 0
    while index < len(lines):
        marker_match = _FOOTNOTE_ANCHOR_PATTERN.match(lines[index].strip())
        if not marker_match:
            output.append(lines[index])
            index += 1
            continue

        footnote_number = marker_match.group("num")
        index += 1
        while index < len(lines) and not lines[index].strip():
            index += 1

        content_parts: list[str] = []
        while index < len(lines):
            current = lines[index].strip()
            if _FOOTNOTE_ANCHOR_PATTERN.match(current):
                break
            if not current:
                lookahead = index
                while lookahead < len(lines) and not lines[lookahead].strip():
                    lookahead += 1
                if lookahead < len(lines) and _FOOTNOTE_ANCHOR_PATTERN.match(
                    lines[lookahead].strip()
                ):
                    index = lookahead
                    break
                if content_parts:
                    content_parts.append("")
                index += 1
                continue
            content_parts.append(current)
            index += 1

        if content_parts:
            joined_content = " ".join(part for part in content_parts if part).strip()
            output.append(f"[^{footnote_number}]: {joined_content}")
        else:
            output.append(f"[^{footnote_number}]:")

    return "\n".join(output)


def preserve_substack_native_video_embeds(
    article_html: str, raw_html: str, *, source_url: str
) -> str:
    """Replace Substack native video placeholders with a preservable snapshot block."""
    if not article_html or (
        'data-component-name="VideoPlaceholder"' not in article_html
        and 'class="native-video-embed"' not in article_html
    ):
        return article_html

    article_soup = BeautifulSoup(article_html, "html.parser")

    for placeholder in article_soup.select(
        ".native-video-embed,[data-component-name='VideoPlaceholder']"
    ):
        media_upload_id = _extract_media_upload_id(placeholder)
        replacement = article_soup.new_tag("figure")
        replacement["data-native-video"] = "substack"

        poster_url = _extract_rendered_substack_video_poster(raw_html, media_upload_id)
        if poster_url:
            image = article_soup.new_tag(
                "img", src=poster_url, alt="Embedded video preview"
            )
            replacement.append(image)

        caption = article_soup.new_tag("figcaption")
        strong = article_soup.new_tag("strong")
        strong.string = "Embedded video in original post"
        caption.append(strong)
        caption.append(" ")
        link = article_soup.new_tag("a", href=source_url)
        link.string = "View on Substack"
        caption.append(link)
        replacement.append(caption)
        placeholder.replace_with(replacement)

    return str(article_soup)


def _extract_media_upload_id(node) -> str | None:
    data_attrs = node.get("data-attrs")
    if data_attrs:
        try:
            payload = json.loads(data_attrs)
        except json.JSONDecodeError:
            payload = None
        if isinstance(payload, dict):
            media_upload_id = payload.get("mediaUploadId")
            if isinstance(media_upload_id, str) and media_upload_id.strip():
                return media_upload_id.strip()
        match = _SUBSTACK_VIDEO_ATTR_MEDIA_ID.search(data_attrs.lower())
        if match:
            return match.group("id")

    node_id = (node.get("id") or "").strip()
    if node_id.startswith("media-"):
        return node_id.removeprefix("media-").strip() or None
    return None


def _extract_rendered_substack_video_poster(
    raw_html: str, media_upload_id: str | None
) -> str | None:
    if not media_upload_id:
        return None

    container_marker = f'id="media-{media_upload_id}"'
    marker_index = raw_html.find(container_marker)
    if marker_index == -1:
        return None

    snippet = raw_html[marker_index : marker_index + 3000]
    poster_match = _SUBSTACK_VIDEO_POSTER.search(snippet)
    if poster_match is None:
        return None

    poster = (poster_match.group("poster") or "").strip()
    if not poster:
        return None
    return urljoin("https://substack.com", poster)


def cleanup_substack_markdown(markdown: str) -> str:
    """Remove Substack UI chrome and malformed image-control wrappers."""
    if not markdown:
        return markdown

    def _replace_linked_image(match: re.Match[str]) -> str:
        alt_text = (match.group("alt") or "").strip()
        image_url = (match.group("image") or "").strip()
        link_url = (match.group("link") or "").strip()
        if "substackcdn.com/image/fetch/" in link_url and (
            _canonical_image_url(image_url) == _canonical_image_url(link_url)
        ):
            return f"![{alt_text}]({image_url})"
        return f"[![{alt_text}]({image_url})]({link_url})"

    cleaned = _LINKED_IMAGE_PATTERN.sub(_replace_linked_image, markdown)

    def _replace_text_link_image(match: re.Match[str]) -> str:
        label_text = (match.group("label") or "").strip()
        link_url = (match.group("link") or "").strip()
        if not re.search(r"[A-Za-z0-9]", label_text):
            return match.group(0)
        return f"[{label_text}]({link_url})"

    cleaned = _INLINE_IMAGE_LINK_PATTERN.sub(_replace_text_link_image, cleaned)

    cleaned_lines: list[str] = []
    dropped_prefixes = (
        "[subscribe now](",
        "[share](",
        "[](https://substackcdn.com/image/fetch/",
        "](https://substackcdn.com/image/fetch/",
    )
    for line in cleaned.splitlines():
        stripped_line = line.strip()
        lowered_line = stripped_line.lower()
        if lowered_line.startswith(dropped_prefixes) or (
            lowered_line.startswith("thanks for reading ")
            and "post is public" in lowered_line
        ):
            continue
        if re.fullmatch(r">\s*", stripped_line):
            continue
        if _EMPTY_HEADING_PATTERN.fullmatch(stripped_line):
            continue
        if stripped_line.startswith("***Editor:"):
            line = re.sub(r"^\*{3}Editor:\*+\s*", "Editor: ", line)
            line = line.replace("*", "")
            line = re.sub(r"[ \t]{2,}", " ", line).strip()
        if "![](" in line:
            without_images = _EMPTY_IMAGE_PATTERN.sub("", line)
            if re.search(r"[A-Za-z0-9]", without_images):
                line = _EMPTY_IMAGE_PATTERN.sub(" ", line)
                line = re.sub(r"[ \t]{2,}", " ", line).rstrip()
        cleaned_lines.append(line)

    cleaned = "\n".join(cleaned_lines)
    for pattern, flags in (
        (r"<svg\b[^>]*>.*?</svg>", re.IGNORECASE | re.DOTALL),
        (
            r"^\s*\[\s*]\(https://substackcdn\.com/image/fetch/[^)]+\)\s*$\n?",
            re.IGNORECASE | re.MULTILINE,
        ),
        (
            r"^\s*\]\(https://substackcdn\.com/image/fetch/[^)]+\)\s*$\n?",
            re.IGNORECASE | re.MULTILINE,
        ),
    ):
        cleaned = re.sub(pattern, "", cleaned, flags=flags)
    cleaned = _normalize_footnotes(cleaned)
    return re.sub(r"\n{3,}", "\n\n", cleaned).strip()
