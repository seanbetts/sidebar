"""Patreon post snapshot helpers for web-save parsing."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime
from urllib.parse import urlparse

from bs4 import BeautifulSoup

from api.services.web_save_parser_utils import parse_datetime

_PATREON_POST_PATH_RE = re.compile(r"^/posts/[^/?#]+")
_PATREON_DURATION_RE = re.compile(
    r"^P(?:T(?:(?P<hours>\d+)H)?(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+(?:\.\d+)?)S)?)$"
)


@dataclass(frozen=True)
class PatreonPostSnapshot:
    """Compact saved representation for a Patreon locked-preview post."""

    title: str
    markdown: str
    source_url: str
    author: str | None
    published_at: datetime | None
    locked: bool
    duration_seconds: int | None = None


def _canonical_patreon_post_url(url: str) -> str:
    parsed = urlparse(url)
    match = _PATREON_POST_PATH_RE.match(parsed.path or "")
    path = match.group(0) if match else parsed.path
    return parsed._replace(path=path, query="", fragment="").geturl()


def _extract_next_data(soup: BeautifulSoup) -> dict:
    tag = soup.find("script", id="__NEXT_DATA__", type="application/json")
    if tag is None or not tag.string:
        return {}
    try:
        payload = json.loads(tag.string)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _extract_jsonld_objects(soup: BeautifulSoup) -> list[dict]:
    objects: list[dict] = []
    for script in soup.find_all("script", type="application/ld+json"):
        raw = script.string or script.get_text(strip=True)
        if not raw:
            continue
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, list):
            objects.extend(item for item in payload if isinstance(item, dict))
        elif isinstance(payload, dict):
            objects.append(payload)
    return objects


def _find_video_object(objects: list[dict]) -> dict:
    for obj in objects:
        if str(obj.get("@type") or "").lower() == "videoobject":
            return obj
    return {}


def _extract_preview_text(soup: BeautifulSoup) -> str:
    teaser = soup.select_one('[data-tag="teaser-post-content"]')
    if teaser is None:
        return ""
    return " ".join(teaser.get_text(" ", strip=True).split())


def _duration_seconds(value: str | None) -> int | None:
    if not value:
        return None
    match = _PATREON_DURATION_RE.match(value.strip())
    if not match:
        return None
    hours = int(match.group("hours") or 0)
    minutes = int(match.group("minutes") or 0)
    seconds = float(match.group("seconds") or 0)
    total = int(hours * 3600 + minutes * 60 + seconds)
    return total or None


def _format_duration(seconds: int | None) -> str | None:
    if not seconds:
        return None
    hours, remainder = divmod(seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    parts: list[str] = []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if secs and not hours or secs and not minutes:
        parts.append(f"{secs}s")
    return " ".join(parts) or None


def extract_patreon_post_snapshot(
    raw_html: str, url: str
) -> PatreonPostSnapshot | None:
    """Extract a compact snapshot for a Patreon post preview page."""
    parsed = urlparse(url)
    host = parsed.netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    if host != "patreon.com" or not parsed.path.startswith("/posts/"):
        return None
    if not raw_html:
        return None

    soup = BeautifulSoup(raw_html, "html.parser")
    next_data = _extract_next_data(soup)
    page_bootstrap = (
        next_data.get("props", {})
        .get("pageProps", {})
        .get("bootstrapEnvelope", {})
        .get("pageBootstrap", {})
    )
    post_attrs = (
        page_bootstrap.get("post", {}).get("data", {}).get("attributes", {}) or {}
    )
    campaign_attrs = (
        page_bootstrap.get("campaign", {}).get("data", {}).get("attributes", {}) or {}
    )

    locked = post_attrs.get("current_user_can_view") is False
    if not locked:
        return None

    jsonld = _find_video_object(_extract_jsonld_objects(soup))
    title = (
        (post_attrs.get("title") or "").strip()
        or str(jsonld.get("name") or "").strip()
        or str(soup.title.string if soup.title and soup.title.string else "").strip()
    )
    if title.endswith(" | Patreon"):
        title = title[: -len(" | Patreon")].strip()
    if not title:
        return None

    author = (
        (campaign_attrs.get("name") or "").strip()
        or (
            (jsonld.get("author") or {}).get("name", "")
            if isinstance(jsonld.get("author"), dict)
            else ""
        ).strip()
        or None
    )
    published_at = parse_datetime(
        post_attrs.get("published_at") or jsonld.get("datePublished")
    )
    duration_seconds = _duration_seconds(jsonld.get("duration"))
    duration_label = _format_duration(duration_seconds)
    image_url = (
        ((post_attrs.get("image") or {}).get("large_url") or "").strip()
        or str(jsonld.get("thumbnailUrl") or "").strip()
        or None
    )
    source_url = _canonical_patreon_post_url(url)
    preview_text = _extract_preview_text(soup)

    header_bits: list[str] = []
    if author:
        header_bits.append(f"By **{author}**")
    if published_at:
        header_bits.append(published_at.strftime("%B %-d, %Y"))
    if duration_label:
        header_bits.append(duration_label)

    blocks: list[str] = []
    if image_url:
        blocks.append(f"![{title}]({image_url})")
    blocks.append(f"**{title}**")
    if header_bits:
        blocks.append(" · ".join(header_bits))
    blocks.append(
        "This Patreon post appears to be locked. Only the public preview is available."
    )
    if preview_text:
        blocks.append(preview_text)
    blocks.append(f"[View on Patreon]({source_url})")

    return PatreonPostSnapshot(
        title=title,
        markdown="\n\n".join(blocks).strip(),
        source_url=source_url,
        author=author,
        published_at=published_at,
        locked=True,
        duration_seconds=duration_seconds,
    )
