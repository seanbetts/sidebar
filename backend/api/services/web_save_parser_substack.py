"""Substack-specific markdown cleanup helpers for web-save parsing."""

from __future__ import annotations

import re

from api.services.web_save_parser_cleanup import _canonical_image_url

_LINKED_IMAGE_PATTERN = re.compile(
    (
        r"\[\s*!\[(?P<alt>[^\]]*)\]\((?P<image>[^)\s]+)\)"
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
            without_images = re.sub(r"!\[\]\([^)]+\)", "", line)
            if re.search(r"[A-Za-z0-9]", without_images):
                line = re.sub(r"\s*!\[\]\([^)]+\)\s*", " ", line)
                line = re.sub(r"[ \t]{2,}", " ", line).rstrip()
        cleaned_lines.append(line)

    cleaned = "\n".join(cleaned_lines)
    for pattern, flags in (
        (r"<svg\b[^>]*>.*?</svg>", re.IGNORECASE | re.DOTALL),
        (
            r"^\s*\[\s*]\(https://substackcdn\.com/image/fetch/[^)]+\)\s*$\n?",
            re.IGNORECASE | re.MULTILINE,
        ),
    ):
        cleaned = re.sub(pattern, "", cleaned, flags=flags)
    cleaned = _normalize_footnotes(cleaned)
    return re.sub(r"\n{3,}", "\n\n", cleaned).strip()
