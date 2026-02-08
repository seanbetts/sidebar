"""GitHub-specific markdown cleanup helpers for web-save parsing."""

from __future__ import annotations

import re
from urllib.parse import unquote, urlparse


def cleanup_github_markdown(markdown: str) -> str:
    """Remove low-value GitHub README chrome from markdown output."""
    if not markdown:
        return markdown

    image_only_line = re.compile(
        r"^\s*(?:\[\s*)?!\[(?P<alt>[^\]]*)]"
        r"\((?P<img>[^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\)"
        r"(?:\]\((?P<link>[^)\s]+)\))?\s*$",
        re.IGNORECASE,
    )
    thanks_contributors_line = re.compile(
        r"^\s*thanks to all (?:clawtributors|contributors)\s*:?\s*$",
        re.IGNORECASE,
    )
    badge_alt_tokens = (
        "badge",
        "status",
        "build",
        "coverage",
        "release",
        "license",
        "discord",
        "star history",
        "version",
        "stars",
    )

    def _normalized_host(url: str | None) -> str:
        if not url:
            return ""
        parsed = urlparse(unquote(url))
        host = parsed.netloc.lower().strip(".")
        if host.startswith("www."):
            host = host[4:]
        return host

    def _is_heading_anchor_icon_line(line: str) -> bool:
        stripped = line.strip()
        lowered = stripped.lower()
        return (
            stripped.startswith("[<svg")
            and "octicon-link" in lowered
            and "](#" in stripped
            and "</svg>" in lowered
        )

    def _image_line_parts(line: str) -> tuple[str, str, str] | None:
        match = image_only_line.match(line)
        if not match:
            return None
        return (
            (match.group("alt") or "").strip(),
            match.group("img") or "",
            match.group("link") or "",
        )

    def _is_avatar_image_line(line: str) -> bool:
        parts = _image_line_parts(line)
        if not parts:
            lowered_line = unquote(line).lower()
            return (
                "![" in lowered_line and "avatars.githubusercontent.com" in lowered_line
            )
        _alt, img_url, link_url = parts
        for candidate in (img_url, link_url):
            decoded = unquote(candidate).lower()
            if "avatars.githubusercontent.com" in decoded:
                return True
            if _normalized_host(candidate) == "avatars.githubusercontent.com":
                return True
        return False

    def _is_badge_candidate_line(line: str) -> bool:
        parts = _image_line_parts(line)
        if not parts:
            return False
        alt_text, img_url, link_url = parts
        alt_lower = alt_text.lower()
        urls = [url for url in (img_url, link_url) if url]
        decoded_blob = " ".join(unquote(url).lower() for url in urls)
        hosts = {_normalized_host(url) for url in urls}

        if "shields.io" in decoded_blob or "star-history.com" in decoded_blob:
            return True

        return bool(
            hosts.intersection({"img.shields.io", "camo.githubusercontent.com"})
        ) and any(token in alt_lower for token in badge_alt_tokens)

    def _is_star_history_line(line: str) -> bool:
        parts = _image_line_parts(line)
        if not parts:
            return False
        alt_text, img_url, link_url = parts
        alt_lower = alt_text.lower()
        urls = [url for url in (img_url, link_url) if url]
        decoded_blob = " ".join(unquote(url).lower() for url in urls)
        return "star history" in alt_lower or "star-history.com" in decoded_blob

    def _is_prose_line(line: str) -> bool:
        stripped = line.strip()
        if not stripped:
            return False
        if _image_line_parts(stripped):
            return False
        if stripped.startswith(("#", ">", "* ", "- ", "```", "|")):
            return False
        if stripped.startswith("[") and "](" in stripped and len(stripped.split()) <= 4:
            return False
        return bool(re.search(r"[A-Za-z]{3}", stripped))

    cleaned_lines: list[str] = []
    for line in markdown.splitlines():
        if _is_heading_anchor_icon_line(line):
            continue
        if thanks_contributors_line.match(line):
            continue
        if _is_avatar_image_line(line):
            continue
        if _is_star_history_line(line):
            continue
        cleaned_lines.append(line)

    badge_zone_end = len(cleaned_lines)
    for idx, line in enumerate(cleaned_lines):
        if _is_prose_line(line):
            badge_zone_end = idx
            break

    badge_candidate_indexes = [
        idx
        for idx, line in enumerate(cleaned_lines[:badge_zone_end])
        if _is_badge_candidate_line(line)
    ]

    if len(badge_candidate_indexes) >= 2:
        badge_candidate_set = set(badge_candidate_indexes)
        cleaned_lines = [
            line
            for idx, line in enumerate(cleaned_lines)
            if idx not in badge_candidate_set
        ]

    cleaned = "\n".join(cleaned_lines)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()
