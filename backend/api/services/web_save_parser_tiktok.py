"""TikTok snapshot helpers for web-save parsing."""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from urllib.parse import quote_plus

import requests

from api.services.web_save_constants import USER_AGENT
from api.services.web_save_parser_utils import ensure_url

logger = logging.getLogger(__name__)

_TIKTOK_VIDEO_RE = re.compile(
    r"^https?://(?:www\.)?tiktok\.com/@(?P<handle>[^/]+)/video/(?P<id>\d+)(?:[/?#].*)?$",
    re.IGNORECASE,
)

_OEMBED_URL = "https://www.tiktok.com/oembed?url={}"


@dataclass(frozen=True)
class TikTokVideoSnapshot:
    """Compact representation of a TikTok video that can be saved."""

    title: str
    source_url: str
    video_id: str
    author_name: str | None
    author_url: str | None
    thumbnail_url: str


def is_tiktok_video_url(url: str) -> bool:
    """Return True when the URL matches the handled TikTok video pattern."""
    try:
        normalized = ensure_url(url)
    except AttributeError:
        return False
    return _TIKTOK_VIDEO_RE.match(normalized) is not None


def _parse_tiktok_video_url(url: str) -> tuple[str, str] | None:
    normalized = ensure_url(url)
    match = _TIKTOK_VIDEO_RE.match(normalized)
    if not match:
        return None
    return match.group("handle"), match.group("id")


def _build_canonical_url(handle: str, video_id: str) -> str:
    return f"https://www.tiktok.com/@{handle}/video/{video_id}"


def _build_oembed_url(source_url: str) -> str:
    return _OEMBED_URL.format(quote_plus(source_url))


def _normalize_optional_url(value: str | None) -> str | None:
    if not value:
        return None
    return ensure_url(value)


def _fetch_oembed_payload(source_url: str, *, timeout: int) -> dict | None:
    try:
        response = requests.get(
            _build_oembed_url(source_url),
            headers={"User-Agent": USER_AGENT},
            timeout=timeout,
        )
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError) as exc:
        logger.debug("TikTok oEmbed request failed for %s: %s", source_url, exc)
        return None

    if not isinstance(payload, dict):
        return None
    return payload


def fetch_tiktok_video_snapshot(
    url: str, *, timeout: int = 8
) -> TikTokVideoSnapshot | None:
    """Return TikTok video snapshot metadata via the public oEmbed endpoint."""
    parsed = _parse_tiktok_video_url(url)
    if not parsed:
        return None
    handle, video_id = parsed
    source_url = _build_canonical_url(handle, video_id)
    payload = _fetch_oembed_payload(source_url, timeout=timeout)
    if not payload:
        return None

    title = payload.get("title") or f"TikTok video by @{handle}"
    author_name = payload.get("author_name")
    remote_author_url = payload.get("author_url")
    author_url = (
        _normalize_optional_url(remote_author_url)
        or f"https://www.tiktok.com/@{handle}"
    )
    thumbnail_url = _normalize_optional_url(payload.get("thumbnail_url"))
    if not thumbnail_url:
        return None

    response_video_id = (
        payload.get("embed_product_id") or payload.get("video_id") or video_id
    )
    return TikTokVideoSnapshot(
        title=title,
        source_url=source_url,
        video_id=str(response_video_id),
        author_name=author_name,
        author_url=author_url,
        thumbnail_url=thumbnail_url,
    )


def build_tiktok_snapshot_markdown(snapshot: TikTokVideoSnapshot) -> str:
    """Return the deterministic markdown that describes the TikTok embed block."""
    marker_payload = {
        "source_url": snapshot.source_url,
        "video_id": snapshot.video_id,
        "author_name": snapshot.author_name,
        "author_url": snapshot.author_url,
        "title": snapshot.title,
        "thumbnail_url": snapshot.thumbnail_url,
    }
    marker = json.dumps(marker_payload, ensure_ascii=False, separators=(",", ":"))
    return (
        f"![TikTok thumbnail]({snapshot.thumbnail_url})\n\n"
        f"<!-- TIKTOK_EMBED: {marker} -->\n\n"
        f"[Open on TikTok]({snapshot.source_url})"
    )
