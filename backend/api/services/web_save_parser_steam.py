"""Steam Community announcement extraction helpers for web-save parsing."""

from __future__ import annotations

import html
import json
import re
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup

STEAM_STORE_SELECTOR = "[data-partnereventstore]"
STEAM_CLAN_IMAGE_BASE = "https://clan.akamai.steamstatic.com/images/"
STEAM_INLINE_TAGS = {
    "b": ("<strong>", "</strong>"),
    "i": ("<em>", "</em>"),
    "u": ("<u>", "</u>"),
    "p": ("<p>", "</p>"),
    "h1": ("<h1>", "</h1>"),
    "h2": ("<h2>", "</h2>"),
    "h3": ("<h3>", "</h3>"),
}
STEAM_URL_RE = re.compile(
    r"""\[url=(?:"(?P<quoted>[^"]+)"|(?P<bare>[^\]]+))\](?P<label>.*?)\[/url\]""",
    re.IGNORECASE | re.DOTALL,
)
STEAM_IMG_ATTR_RE = re.compile(
    r"""\[img\s+src=(?:"(?P<quoted>[^"]+)"|(?P<bare>[^\]]+))\]""",
    re.IGNORECASE | re.DOTALL,
)
STEAM_IMG_RE = re.compile(r"\[img\](?P<url>.*?)\[/img\]", re.IGNORECASE | re.DOTALL)
STEAM_LIST_RE = re.compile(r"\[list\](?P<body>.*?)\[/list\]", re.IGNORECASE | re.DOTALL)
STEAM_YOUTUBE_RE = re.compile(
    r"\[previewyoutube=(?P<id>[^;\]]+)(?:;[^\]]*)?\](?P<label>.*?)\[/previewyoutube\]",
    re.IGNORECASE | re.DOTALL,
)
STEAM_REMINDME_RE = re.compile(
    r"\[remindme\].*?\[/remindme\]", re.IGNORECASE | re.DOTALL
)
STEAM_TAG_RE = re.compile(
    r"\[(?P<closing>/)?(?P<tag>b|i|u|p|h1|h2|h3)(?:\s+[^\]]+)?\]",
    re.IGNORECASE,
)
STEAM_LEFTOVER_TAG_RE = re.compile(r"\[/?[a-z0-9*]+(?:=[^\]]+)?\]", re.IGNORECASE)


def _extract_requested_gid(url: str) -> str | None:
    segments = [segment for segment in urlparse(url).path.split("/") if segment]
    for segment in reversed(segments):
        if segment.isdigit():
            return segment
    return None


def _load_event_store(raw_html: str) -> list[dict]:
    soup = BeautifulSoup(raw_html, "html.parser")
    store_tag = soup.select_one(STEAM_STORE_SELECTOR)
    if not store_tag:
        return []
    store_value = store_tag.get("data-partnereventstore")
    if not isinstance(store_value, str) or not store_value.strip():
        return []
    try:
        payload = json.loads(html.unescape(store_value))
    except json.JSONDecodeError:
        return []
    return payload if isinstance(payload, list) else []


def _event_matches_gid(event: dict, requested_gid: str | None) -> bool:
    if not requested_gid:
        return False
    announcement = event.get("announcement_body") or {}
    candidate_ids = {
        str(event.get("gid") or ""),
        str(event.get("news_post_gid") or ""),
        str(announcement.get("gid") or ""),
        str(announcement.get("event_gid") or ""),
    }
    return requested_gid in candidate_ids


def _select_event(events: list[dict], requested_gid: str | None) -> dict | None:
    for event in events:
        if _event_matches_gid(event, requested_gid):
            return event
    return events[0] if len(events) == 1 else None


def _render_steam_list(match: re.Match[str]) -> str:
    items = [
        item.strip()
        for item in re.split(r"\[\*\]", match.group("body"))
        if item.strip()
    ]
    if not items:
        return ""
    rendered = "".join(f"<li>{item}</li>" for item in items)
    return f"<ul>{rendered}</ul>"


def _render_steam_url(match: re.Match[str]) -> str:
    href = html.escape(match.group("quoted") or match.group("bare") or "", quote=True)
    label = (match.group("label") or "").strip() or href
    return f'<a href="{href}">{label}</a>'


def _normalize_steam_image_url(raw_src: str | None) -> str:
    src = (raw_src or "").strip()
    if not src:
        return ""
    src = src.replace("{STEAM_CLAN_IMAGE}/", STEAM_CLAN_IMAGE_BASE)
    src = src.replace("{STEAM_CLAN_LOC_IMAGE}/", STEAM_CLAN_IMAGE_BASE)
    if src.startswith("/"):
        src = urljoin(STEAM_CLAN_IMAGE_BASE, src.lstrip("/"))
    return src


def _render_steam_image_url(raw_src: str | None) -> str:
    src = html.escape(_normalize_steam_image_url(raw_src), quote=True)
    if not src:
        return ""
    return f'<img src="{src}" alt="Steam announcement image"/>'


def _render_steam_image_attr(match: re.Match[str]) -> str:
    return _render_steam_image_url(match.group("quoted") or match.group("bare"))


def _render_steam_image(match: re.Match[str]) -> str:
    return _render_steam_image_url(match.group("url"))


def _render_steam_youtube(match: re.Match[str]) -> str:
    video_id = (match.group("id") or "").strip()
    if not video_id:
        return ""
    label = (match.group("label") or "").strip() or "Watch on YouTube"
    return f'<p><a href="https://www.youtube.com/watch?v={video_id}">{label}</a></p>'


def _render_inline_tags(raw_text: str) -> str:
    def replace_tag(match: re.Match[str]) -> str:
        opening, closing = STEAM_INLINE_TAGS[match.group("tag").lower()]
        return closing if match.group("closing") else opening

    return STEAM_TAG_RE.sub(replace_tag, raw_text)


def _normalize_steam_markup(raw_text: str) -> str:
    text = (
        (raw_text or "").replace("\r\n", "\n").replace("\r", "\n").replace("\xa0", " ")
    )
    text = STEAM_REMINDME_RE.sub("", text)
    text = STEAM_YOUTUBE_RE.sub(_render_steam_youtube, text)
    text = STEAM_LIST_RE.sub(_render_steam_list, text)
    text = STEAM_URL_RE.sub(_render_steam_url, text)
    text = STEAM_IMG_ATTR_RE.sub(_render_steam_image_attr, text)
    text = STEAM_IMG_RE.sub(_render_steam_image, text)
    text = _render_inline_tags(text)
    text = STEAM_LEFTOVER_TAG_RE.sub("", text)
    return text


def _cleanup_steam_html(html_fragment: str) -> str:
    soup = BeautifulSoup(f"<div>{html_fragment}</div>", "html.parser")
    container = soup.div
    if container is None:
        return html_fragment

    for tag in container.find_all(["p", "h1", "h2", "h3", "li", "a"]):
        text = tag.get_text(" ", strip=True)
        if tag.name in {"p", "li"} and not text and not tag.find("img"):
            tag.decompose()

    cleaned = str(container)
    cleaned = cleaned.removeprefix("<div>").removesuffix("</div>")
    return cleaned.strip()


def extract_steamcommunity_body_html(raw_html: str, url: str) -> str | None:
    """Extract Steam announcement body HTML from embedded event-store data."""
    if not raw_html:
        return None
    events = _load_event_store(raw_html)
    event = _select_event(events, _extract_requested_gid(url))
    if not event:
        return None

    announcement = event.get("announcement_body") or {}
    body = announcement.get("body")
    if not isinstance(body, str) or not body.strip():
        return None

    rendered_body = _normalize_steam_markup(body)
    cleaned_body = _cleanup_steam_html(rendered_body)
    if not cleaned_body:
        return None

    return f"<html><body>{cleaned_body}</body></html>"
