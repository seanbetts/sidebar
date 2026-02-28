"""WSJ-specific preview detection and enrichment helpers."""

from __future__ import annotations

import logging
import re
from typing import TypedDict

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

_WSJ_FOOTER_MARKERS = (
    "mod=wsjfooter",
    "customercenter.wsj.com",
    "subscribe.wsj.com",
    "corporate.wsj.com",
    "wsj.jobs",
    "djreprints.com",
    "dowjones.com/privacy-notice",
    "wsj.com/policy/legal-policies",
    "dowjones.com/terms-of-use",
    "facebook.com/wsj",
    "twitter.com/wsj",
    "instagram.com/wsj",
)
_WSJ_PAYWALL_MARKERS = (
    "continue reading your article with",
    "a wsj subscription",
    "subscribe now",
    "subscriber agreement",
)
_TRUNCATION_WARNING = (
    "Warning: This article appears truncated. Full content may be behind a paywall."
)


class WSJFlags(TypedDict):
    """WSJ content flags used for save metadata."""

    paywalled: bool
    truncated: bool


class WSJPreviewEnrichmentError(RuntimeError):
    """Raised when WSJ preview enrichment is required but unavailable."""


def _is_wsj_domain(domain: str) -> bool:
    return domain == "wsj.com" or domain.endswith(".wsj.com")


def _has_paywall_marker(*parts: str) -> bool:
    lowered = "\n".join(part.lower() for part in parts if part)
    return any(marker in lowered for marker in _WSJ_PAYWALL_MARKERS)


def _has_footer_noise(markdown: str) -> bool:
    lowered = markdown.lower()
    return any(marker in lowered for marker in _WSJ_FOOTER_MARKERS)


def _quality_score(markdown: str) -> int:
    word_count = compute_word_count(markdown)
    noisy_list_lines = sum(
        1
        for line in markdown.splitlines()
        if line.lstrip().startswith("*") and "](" in line
    )
    footer_hits = sum(1 for marker in _WSJ_FOOTER_MARKERS if marker in markdown.lower())
    penalty = (noisy_list_lines * 12) + (footer_hits * 45)
    return max(word_count - penalty, 0)


def _is_likely_wsj_preview_content(
    *, domain: str, raw_html: str, markdown: str
) -> bool:
    """Return True when WSJ content resembles a truncated paywall preview."""
    if not _is_wsj_domain(domain):
        return False
    has_paywall_marker = _has_paywall_marker(raw_html, markdown)
    has_copyright_marker = bool(_WSJ_COPYRIGHT_RE.search(markdown))
    word_count = compute_word_count(markdown)
    has_footer_noise = _has_footer_noise(markdown)
    if has_paywall_marker:
        return True
    if has_copyright_marker and word_count < 900:
        return True
    return has_footer_noise and word_count < 900


def apply_wsj_content_guards(
    *,
    domain: str,
    raw_html: str,
    marker_markdown: str,
    markdown: str,
) -> tuple[str, WSJFlags]:
    """Annotate likely truncated WSJ content and return flags for frontmatter."""
    if not domain.endswith("wsj.com"):
        return markdown, {"paywalled": False, "truncated": False}
    has_paywall_marker = _has_paywall_marker(raw_html, marker_markdown, markdown)
    has_copyright_marker = bool(_WSJ_COPYRIGHT_RE.search(marker_markdown)) or bool(
        _WSJ_COPYRIGHT_RE.search(markdown)
    )
    has_footer_noise = _has_footer_noise(marker_markdown) or _has_footer_noise(markdown)
    word_count = compute_word_count(markdown)
    is_truncated = has_paywall_marker or (
        (has_copyright_marker or has_footer_noise) and word_count < 900
    )
    if (
        is_truncated
        and markdown.strip()
        and not markdown.lstrip().startswith(_TRUNCATION_WARNING)
    ):
        markdown = f"{_TRUNCATION_WARNING}\n\n{markdown.strip()}"
    flags: WSJFlags = {
        "paywalled": is_truncated,
        "truncated": is_truncated,
    }
    return markdown, flags


def maybe_enrich_wsj_preview(
    *,
    domain: str,
    final_url: str,
    source_url: str,
    raw_html: str,
    markdown: str,
    title: str,
) -> tuple[str, str, str, str | None, WSJFlags]:
    """Use Jina content when a WSJ preview snippet is detected and Jina is better."""
    if not _is_wsj_domain(domain):
        return (
            markdown,
            source_url,
            title,
            None,
            {"paywalled": False, "truncated": False},
        )
    local_marker_markdown = markdown
    local_cleaned = JinaService.clean_markdown_for_source(markdown, source_url)
    if not _is_likely_wsj_preview_content(
        domain=domain,
        raw_html=raw_html,
        markdown=local_marker_markdown,
    ):
        local_cleaned, flags = apply_wsj_content_guards(
            domain=domain,
            raw_html=raw_html,
            marker_markdown=local_marker_markdown,
            markdown=local_cleaned,
        )
        return local_cleaned, source_url, title, None, flags

    local_word_count = compute_word_count(local_cleaned)
    local_quality = _quality_score(local_cleaned)
    if not settings.jina_api_key.strip():
        logger.info(
            "web-save wsj preview detected url=%s mode=raise-error no_jina_key=1",
            final_url,
        )
        raise WSJPreviewEnrichmentError(
            "WSJ preview detected but Jina fallback is unavailable: "
            "JINA_API_KEY is not configured."
        )

    try:
        jina_markdown = JinaService.fetch_markdown(source_url)
        jina_metadata, jina_marker_markdown = JinaService.parse_metadata(jina_markdown)
        jina_source = jina_metadata.get("url_source") or source_url
        jina_cleaned = JinaService.clean_markdown_for_source(
            jina_marker_markdown,
            jina_source,
        )
        jina_word_count = compute_word_count(jina_cleaned)
        jina_quality = _quality_score(jina_cleaned)
        if (
            jina_quality > local_quality + 80
            or (
                jina_quality >= local_quality - 30
                and jina_word_count > local_word_count + 180
            )
            or (
                _has_footer_noise(local_marker_markdown)
                and not _has_footer_noise(jina_marker_markdown)
                and jina_word_count >= local_word_count - 80
            )
        ):
            jina_cleaned, flags = apply_wsj_content_guards(
                domain=domain,
                raw_html="",
                marker_markdown=jina_marker_markdown,
                markdown=jina_cleaned,
            )
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
                    "local_words=%s jina_words=%s local_quality=%s jina_quality=%s"
                ),
                final_url,
                local_word_count,
                jina_word_count,
                local_quality,
                jina_quality,
            )
            return (
                jina_cleaned,
                jina_source,
                resolved_title,
                jina_metadata.get("published_time"),
                flags,
            )

        logger.info(
            (
                "web-save wsj preview detected url=%s mode=keep-local "
                "local_words=%s jina_words=%s local_quality=%s jina_quality=%s"
            ),
            final_url,
            local_word_count,
            jina_word_count,
            local_quality,
            jina_quality,
        )
        local_cleaned, flags = apply_wsj_content_guards(
            domain=domain,
            raw_html=raw_html,
            marker_markdown=local_marker_markdown,
            markdown=local_cleaned,
        )
        return local_cleaned, source_url, title, None, flags
    except Exception as exc:
        logger.info(
            ("web-save wsj preview detected url=%s mode=raise-error jina_error=%s"),
            final_url,
            str(exc),
        )
        raise WSJPreviewEnrichmentError(
            f"WSJ preview detected but Jina fallback failed: {exc}"
        ) from exc
