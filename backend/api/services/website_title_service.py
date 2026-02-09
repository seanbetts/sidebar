"""Helpers for normalizing and recovering website titles."""

from __future__ import annotations

import json
import logging
import re
from urllib.parse import quote_plus

import requests
from bs4 import BeautifulSoup

from api.services.url_normalization_service import extract_youtube_video_id
from api.services.web_save_constants import USER_AGENT

logger = logging.getLogger(__name__)

NULL_LIKE_VALUES = {"undefined", "null", "none", "n/a"}
YOUTUBE_PLACEHOLDER_VALUES = {
    "youtube",
    "- youtube",
    "watch on youtube",
    "youtube -",
}
YOUTUBE_SUFFIX_RE = re.compile(r"\s*-\s*YouTube\s*$", re.IGNORECASE)


def _clean_title_value(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = " ".join(value.strip().split())
    if not cleaned:
        return None
    if cleaned.lower() in NULL_LIKE_VALUES:
        return None
    return cleaned


def normalize_youtube_title(value: str | None) -> str | None:
    """Normalize YouTube title strings and drop placeholder-only values."""
    cleaned = _clean_title_value(value)
    if cleaned is None:
        return None
    without_suffix = YOUTUBE_SUFFIX_RE.sub("", cleaned).strip()
    cleaned = without_suffix if without_suffix else cleaned
    lowered = cleaned.lower().strip()
    if lowered in YOUTUBE_PLACEHOLDER_VALUES:
        return None
    if all(char in "-–—" for char in lowered):
        return None
    return cleaned


def _iter_jsonld_titles(raw_html: str) -> list[str]:
    soup = BeautifulSoup(raw_html, "html.parser")
    titles: list[str] = []
    for script in soup.find_all("script", attrs={"type": "application/ld+json"}):
        if not script.string:
            continue
        try:
            payload = json.loads(script.string)
        except json.JSONDecodeError:
            continue
        queue: list[object] = [payload]
        while queue:
            current = queue.pop(0)
            if isinstance(current, list):
                queue.extend(current)
                continue
            if not isinstance(current, dict):
                continue
            for key in ("name", "headline", "title"):
                value = current.get(key)
                if isinstance(value, str):
                    titles.append(value)
            queue.extend(current.values())
    return titles


def extract_youtube_title_from_html(raw_html: str) -> str | None:
    """Extract a best-effort YouTube title from HTML/meta/json-ld."""
    if not raw_html:
        return None

    soup = BeautifulSoup(raw_html, "html.parser")
    candidates: list[str | None] = [
        (
            soup.find("meta", attrs={"property": "og:title"}).get("content")
            if soup.find("meta", attrs={"property": "og:title"})
            else None
        ),
        (
            soup.find("meta", attrs={"name": "twitter:title"}).get("content")
            if soup.find("meta", attrs={"name": "twitter:title"})
            else None
        ),
        (
            soup.find("meta", attrs={"itemprop": "name"}).get("content")
            if soup.find("meta", attrs={"itemprop": "name"})
            else None
        ),
        soup.title.string if soup.title and soup.title.string else None,
    ]

    for value in candidates:
        normalized = normalize_youtube_title(value)
        if normalized:
            return normalized

    for value in _iter_jsonld_titles(raw_html):
        normalized = normalize_youtube_title(value)
        if normalized:
            return normalized
    return None


def fetch_youtube_oembed_title(url: str, *, timeout: int = 8) -> str | None:
    """Fetch YouTube title via oEmbed for fallback title recovery."""
    video_id = extract_youtube_video_id(url)
    if not video_id:
        return None
    watch_url = f"https://www.youtube.com/watch?v={video_id}"
    oembed_url = (
        "https://www.youtube.com/oembed" f"?url={quote_plus(watch_url)}&format=json"
    )
    try:
        response = requests.get(
            oembed_url,
            headers={"User-Agent": USER_AGENT},
            timeout=timeout,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception:
        return None
    return normalize_youtube_title(payload.get("title"))


def resolve_website_title(
    title: str | None,
    *,
    url: str,
    raw_html: str | None = None,
    allow_network: bool = True,
) -> str | None:
    """Resolve a cleaned website title, repairing weak YouTube placeholders."""
    cleaned = _clean_title_value(title)
    if extract_youtube_video_id(url) is None:
        return cleaned

    normalized = normalize_youtube_title(cleaned)
    if normalized:
        return normalized

    if raw_html:
        html_title = extract_youtube_title_from_html(raw_html)
        if html_title:
            return html_title

    if allow_network:
        oembed_title = fetch_youtube_oembed_title(url)
        if oembed_title:
            return oembed_title

    logger.info("youtube title fallback unresolved url=%s candidate=%s", url, cleaned)
    return None
