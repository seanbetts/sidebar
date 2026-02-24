"""WSJ-specific preview detection and enrichment helpers."""

from __future__ import annotations

import logging
import re

from api.config import settings
from api.services.jina_service import JinaService
from api.services.web_save_tagger import compute_word_count
from api.services.website_title_service import resolve_website_title

logger = logging.getLogger(__name__)

_WSJ_COPYRIGHT_RE = re.compile(
    (
        r"Copyright ©\d{4} Dow Jones & Company, Inc\. All Rights Reserved\."
        r"(?: [a-f0-9]{32})?"
    ),
    re.IGNORECASE,
)


def _is_likely_wsj_preview_content(
    *,
    domain: str,
    raw_html: str,
    markdown: str,
) -> bool:
    """Return True when WSJ content resembles a short paywall preview snippet."""
    if not domain.endswith("wsj.com"):
        return False

    word_count = compute_word_count(markdown)
    if word_count >= 700:
        return False

    lowered_html = raw_html.lower()
    lowered_markdown = markdown.lower()
    paywall_markers = (
        "continue reading your article with",
        "a wsj subscription",
    )
    has_paywall_marker = any(
        marker in lowered_html or marker in lowered_markdown
        for marker in paywall_markers
    )
    has_copyright_marker = bool(_WSJ_COPYRIGHT_RE.search(markdown))
    return has_paywall_marker or has_copyright_marker


def maybe_enrich_wsj_preview(
    *,
    domain: str,
    final_url: str,
    source_url: str,
    raw_html: str,
    markdown: str,
    title: str,
) -> tuple[str, str, str, str | None]:
    """Use Jina content when a WSJ preview snippet is detected and Jina is better."""
    if not _is_likely_wsj_preview_content(
        domain=domain,
        raw_html=raw_html,
        markdown=markdown,
    ):
        return markdown, source_url, title, None

    local_word_count = compute_word_count(markdown)
    if not settings.jina_api_key.strip():
        logger.info(
            "web-save wsj preview detected url=%s mode=keep-local no_jina_key=1",
            final_url,
        )
        return markdown, source_url, title, None

    try:
        jina_markdown = JinaService.fetch_markdown(source_url)
        jina_metadata, jina_cleaned = JinaService.parse_metadata(jina_markdown)
        jina_source = jina_metadata.get("url_source") or source_url
        jina_cleaned = JinaService.clean_markdown_for_source(
            jina_cleaned,
            jina_source,
        )
        jina_word_count = compute_word_count(jina_cleaned)
        if jina_word_count > local_word_count:
            resolved_title = (
                resolve_website_title(
                    jina_metadata.get("title") or title,
                    url=jina_source,
                    raw_html=raw_html,
                )
                or title
            )
            logger.info(
                (
                    "web-save wsj preview detected url=%s mode=use-jina "
                    "local_words=%s jina_words=%s"
                ),
                final_url,
                local_word_count,
                jina_word_count,
            )
            return (
                jina_cleaned,
                jina_source,
                resolved_title,
                jina_metadata.get("published_time"),
            )

        logger.info(
            (
                "web-save wsj preview detected url=%s mode=keep-local "
                "local_words=%s jina_words=%s"
            ),
            final_url,
            local_word_count,
            jina_word_count,
        )
        return markdown, source_url, title, None
    except Exception as exc:
        logger.info(
            ("web-save wsj preview detected url=%s mode=keep-local " "jina_error=%s"),
            final_url,
            str(exc),
        )
        return markdown, source_url, title, None
