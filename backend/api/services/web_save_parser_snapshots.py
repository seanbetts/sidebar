"""Helpers for rendering domain-specific snapshot metadata."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

from api.services.web_save_parser_patreon import (
    PatreonPostSnapshot,
    extract_patreon_post_snapshot,
)
from api.services.web_save_parser_twitter import (
    TwitterStatusSnapshot,
    fetch_twitter_status_snapshot,
)
from api.services.web_save_tagger import compute_word_count, count_images, extract_tags
from api.services.website_reading_time import (
    page_reading_time,
    reading_time_from_duration_seconds,
)


@dataclass(frozen=True)
class SnapshotRender:
    """Normalized markdown and frontmatter metadata for a saved snapshot."""

    title: str
    source: str
    markdown: str
    published_at: datetime | None
    meta: dict
    kind: str
    locked: bool = False


def build_twitter_snapshot_render(
    snapshot: TwitterStatusSnapshot,
    *,
    raw_html: str,
    used_js_rendering: bool,
) -> SnapshotRender:
    """Build metadata for a Twitter/X snapshot page."""
    source_url = snapshot.source_url
    title = snapshot.title
    domain = source_url.split("/", 3)[2]
    markdown = snapshot.markdown
    word_count = compute_word_count(markdown)
    image_count = count_images(markdown)
    return SnapshotRender(
        title=title,
        source=source_url,
        markdown=markdown,
        published_at=None,
        meta={
            "source": source_url,
            "title": title,
            "author": snapshot.author,
            "domain": domain,
            "word_count": word_count,
            "reading_time": page_reading_time(
                word_count, image_count, domain, raw_html
            ),
            "tags": extract_tags(markdown, domain, title),
            "used_js_rendering": used_js_rendering,
            "saved_at": datetime.now(UTC).isoformat(),
        },
        kind="x",
    )


def build_patreon_snapshot_render(
    snapshot: PatreonPostSnapshot,
    *,
    raw_html: str,
    used_js_rendering: bool,
) -> SnapshotRender:
    """Build metadata for a Patreon preview snapshot page."""
    source_url = snapshot.source_url
    title = snapshot.title
    domain = source_url.split("/", 3)[2]
    markdown = snapshot.markdown
    word_count = compute_word_count(markdown)
    image_count = count_images(markdown)
    reading_time = reading_time_from_duration_seconds(
        snapshot.duration_seconds
    ) or page_reading_time(word_count, image_count, domain, raw_html)
    return SnapshotRender(
        title=title,
        source=source_url,
        markdown=markdown,
        published_at=snapshot.published_at,
        meta={
            "source": source_url,
            "title": title,
            "author": snapshot.author,
            "published_date": (
                snapshot.published_at.isoformat() if snapshot.published_at else None
            ),
            "domain": domain,
            "word_count": word_count,
            "reading_time": reading_time,
            "tags": extract_tags(markdown, domain, title),
            "used_js_rendering": used_js_rendering,
            "paywalled": snapshot.locked,
            "truncated": snapshot.locked,
            "saved_at": datetime.now(UTC).isoformat(),
        },
        kind="patreon",
        locked=snapshot.locked,
    )


def maybe_build_snapshot_render(
    final_url: str,
    *,
    raw_html: str,
    used_js_rendering: bool,
    twitter_fetcher=fetch_twitter_status_snapshot,
    patreon_extractor=extract_patreon_post_snapshot,
) -> SnapshotRender | None:
    """Return a rendered snapshot payload for supported domain-specific previews."""
    twitter_snapshot = twitter_fetcher(final_url)
    if twitter_snapshot:
        return build_twitter_snapshot_render(
            twitter_snapshot,
            raw_html=raw_html,
            used_js_rendering=used_js_rendering,
        )

    patreon_snapshot = patreon_extractor(raw_html, final_url)
    if patreon_snapshot:
        return build_patreon_snapshot_render(
            patreon_snapshot,
            raw_html=raw_html,
            used_js_rendering=used_js_rendering,
        )

    return None
