"""Domain-specific article extraction routing helpers."""

from __future__ import annotations

from collections.abc import Mapping
from urllib.parse import urlparse

from api.services.web_save_parser_bbc import extract_bbc_body_html
from api.services.web_save_parser_blog_google import extract_blog_google_body_html
from api.services.web_save_parser_cleanup import (
    extract_openai_body_html,
    extract_verge_body_html,
    extract_wired_body_html,
)
from api.services.web_save_parser_gameinformer import extract_gameinformer_body_html
from api.services.web_save_parser_hbr import extract_hbr_body_html
from api.services.web_save_parser_reuters import extract_reuters_payload
from api.services.web_save_parser_sidebar_docs import extract_sidebar_docs_body_html
from api.services.web_save_parser_steam import extract_steamcommunity_payload_for_url


def apply_domain_specific_extractor(
    article_html: str,
    *,
    final_url: str,
    raw_html: str,
) -> tuple[str, dict[str, str | None], bool]:
    """Return domain-specific article HTML, metadata overrides, and blog ordering."""
    empty_metadata: dict[str, str | None] = {}
    domain = urlparse(final_url).netloc
    if domain.endswith("openai.com"):
        return extract_openai_body_html(raw_html) or article_html, empty_metadata, False
    if domain.endswith("wired.com"):
        return extract_wired_body_html(raw_html) or article_html, empty_metadata, False
    if domain.endswith("theverge.com"):
        return extract_verge_body_html(raw_html) or article_html, empty_metadata, False
    if domain.endswith("bbc.com"):
        bbc_payload = extract_bbc_body_html(raw_html)
        if bbc_payload:
            bbc_html, bbc_meta = bbc_payload
            return bbc_html, _coerce_metadata(bbc_meta), False
    if steam_payload := extract_steamcommunity_payload_for_url(raw_html, final_url):
        steam_html, steam_meta = steam_payload
        return steam_html, _coerce_metadata(steam_meta), False
    if reuters_payload := extract_reuters_payload(raw_html, final_url):
        reuters_html, reuters_meta = reuters_payload
        return reuters_html, _coerce_metadata(reuters_meta), False
    if domain.endswith("gameinformer.com"):
        return (
            extract_gameinformer_body_html(raw_html) or article_html,
            empty_metadata,
            False,
        )
    if domain.endswith("docs.trysidebar.ai"):
        return (
            extract_sidebar_docs_body_html(raw_html) or article_html,
            empty_metadata,
            False,
        )
    if domain.endswith("blog.google"):
        blog_html = extract_blog_google_body_html(raw_html)
        return (blog_html or article_html), empty_metadata, bool(blog_html)
    if domain.endswith("hbr.org"):
        hbr_payload = extract_hbr_body_html(raw_html)
        if hbr_payload:
            hbr_html, hbr_meta = hbr_payload
            return hbr_html, _coerce_metadata(hbr_meta), False
    return article_html, empty_metadata, False


def _coerce_metadata(metadata: Mapping[str, str | None]) -> dict[str, str | None]:
    """Normalize metadata to the parser routing contract."""
    return dict(metadata)
