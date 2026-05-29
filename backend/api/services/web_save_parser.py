"""Local parsing utilities for the web-save skill."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from functools import lru_cache
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
import yaml
from bs4 import BeautifulSoup
from markdownify import MarkdownConverter

try:
    from readability import Document as ReadabilityDocument
except (ImportError, AttributeError):
    ReadabilityDocument = None

from api.services import web_save_parser_metadata
from api.services.web_save_constants import USER_AGENT
from api.services.web_save_includes import apply_include_reinsertion
from api.services.web_save_parser_apple_news import maybe_unwrap_apple_news
from api.services.web_save_parser_cleanup import (
    cleanup_gizmodo_markdown,
    cleanup_verge_markdown,
    cleanup_youtube_markdown,
    dedupe_markdown_blocks,
    dedupe_markdown_images,
    filter_non_content_images,
    is_paywalled,
    normalize_image_captions,
    normalize_image_sources,
    normalize_link_sources,
    normalize_wired_image_url,
    polish_article_html,
    prepend_hero_image,
    simplify_linked_images,
    wrap_gallery_blocks,
)
from api.services.web_save_parser_domain_extractors import (
    apply_domain_specific_extractor,
)
from api.services.web_save_parser_fallback import (
    LocalParseFallbackError,
    raise_antibot_fallback_if_needed,
)
from api.services.web_save_parser_forbes import extract_forbes_article_markdown
from api.services.web_save_parser_ft import extract_ft_barrier_payload
from api.services.web_save_parser_github import cleanup_github_markdown
from api.services.web_save_parser_html import _safe_html_tostring, _safe_html_tree
from api.services.web_save_parser_metadata import extract_metadata
from api.services.web_save_parser_openai import cleanup_openai_markdown
from api.services.web_save_parser_patreon import extract_patreon_post_snapshot
from api.services.web_save_parser_paywall import (
    build_paywall_frontmatter,
    extract_paywall_preview_markdown,
    is_anti_bot_challenge_page,
)
from api.services.web_save_parser_snapshots import maybe_build_snapshot_render
from api.services.web_save_parser_substack import (
    cleanup_substack_markdown,
    preserve_substack_native_video_embeds,
)
from api.services.web_save_parser_substack_helpers import (
    is_substack_host,
    match_substack_host_rules,
    merge_rules,
    should_apply_substack_cleanup,
)
from api.services.web_save_parser_tiktok import (
    fetch_tiktok_video_snapshot,
    is_tiktok_video_url,
)
from api.services.web_save_parser_twitter import fetch_twitter_status_snapshot
from api.services.web_save_parser_utils import (
    ensure_url,
    parse_datetime,
    strip_control_chars,
)
from api.services.web_save_parser_wsj import maybe_enrich_wsj_preview
from api.services.web_save_parser_youtube import (
    _iter_youtube_elements as _iter_youtube_elements_impl,
)
from api.services.web_save_parser_youtube import (
    _merge_youtube_anchors,
    build_youtube_anchor_map,
    extract_youtube_anchors_from_jsonld,
    extract_youtube_embed_urls_from_dom,
    extract_youtube_video_id,
    extract_youtube_video_ids_from_html,
    insert_youtube_after_anchors,
    insert_youtube_placeholders,
    replace_youtube_iframes_with_placeholders,
    replace_youtube_placeholders,
)
from api.services.web_save_rendering import (
    render_html_with_playwright,
    resolve_auto_render_wait_until,
    resolve_rendering_settings,
    should_auto_render_url,
)
from api.services.web_save_rules import Rule, RuleEngine, extract_metadata_overrides
from api.services.web_save_tagger import (
    compute_word_count,
    count_images,
    extract_tags,
)
from api.services.website_reading_time import page_reading_time
from api.services.website_title_service import resolve_website_title

logger = logging.getLogger(__name__)

RULES_DIR = Path(__file__).resolve().parents[2] / "skills" / "web-save" / "rules"
PLAYWRIGHT_ALLOWLIST_PATH = RULES_DIR / "playwright_allowlist.yaml"
_iter_youtube_elements = _iter_youtube_elements_impl


@dataclass(frozen=True)
class ParsedPage:
    """Parsed page payload for saving."""

    title: str
    content: str
    source: str
    published_at: datetime | None
    favicon_url: str | None = None


def extract_favicon_url(url: str, *, timeout: int = 15) -> str | None:
    """Fetch HTML and resolve a favicon URL without full parsing."""
    normalized = ensure_url(url)
    try:
        html, final_url, _ = fetch_html(normalized, timeout=timeout)
    except requests.RequestException:
        return None
    html = strip_control_chars(html)
    metadata = extract_metadata(html, final_url)
    return resolve_favicon_url(metadata.get("favicon"), final_url)


def fetch_html(url: str, *, timeout: int = 30) -> tuple[str, str, bool]:
    """Fetch raw HTML and return (html, final_url, used_js_rendering)."""
    headers = {"User-Agent": USER_AGENT}
    try:
        response = requests.get(url, headers=headers, timeout=timeout)
        response.raise_for_status()
        return (
            web_save_parser_metadata.decode_html_response(response),
            str(response.url),
            False,
        )
    except requests.HTTPError as exc:
        status_code = exc.response.status_code if exc.response is not None else None
        if status_code in {401, 403, 429}:
            html, final_url = render_html_with_playwright(
                url,
                timeout=timeout * 1000,
                wait_until="domcontentloaded",
            )
            raise_antibot_fallback_if_needed(html, stage="playwright")
            return html, final_url, True
        raise


def _rel_matches(rel_value: str | list[str] | None, target: str) -> bool:
    """Return True when rel_value includes all tokens from target."""
    return web_save_parser_metadata._rel_matches(rel_value, target)


def _favicon_exists(url: str, *, timeout: int = 8) -> bool:
    """Return True if a favicon URL responds successfully."""
    return web_save_parser_metadata._favicon_exists(url, timeout=timeout)


def resolve_favicon_url(raw_favicon: str | None, source_url: str) -> str | None:
    """Resolve a favicon URL relative to the source URL with fallbacks."""
    if raw_favicon:
        resolved = urljoin(source_url, raw_favicon)
        parsed = urlparse(resolved)
        if parsed.scheme in {"http", "https"}:
            return resolved
        return None

    parsed_source = urlparse(source_url)
    if not parsed_source.scheme or not parsed_source.netloc:
        return None
    fallback = f"{parsed_source.scheme}://{parsed_source.netloc}/favicon.ico"
    if _favicon_exists(fallback):
        return fallback
    return None


def _discard_frontmatter(
    *,
    source: str,
    domain: str,
    rule: Rule | None,
    used_js_rendering: bool,
) -> str:
    reason = "Content discarded by rule"
    if rule:
        reason = f"{reason}: {rule.id}"
    frontmatter_meta = {
        "source": source,
        "domain": domain,
        "discarded": True,
        "discard_reason": reason,
        "rule_id": rule.id if rule else None,
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(UTC).isoformat(),
    }
    return build_frontmatter(
        "[Content discarded by parsing rule]", meta=frontmatter_meta
    )


def _raise_fallback_for_discard_rule(*, rule: Rule, phase: str, url: str) -> None:
    """Raise when a discard rule explicitly requests upstream fallback."""
    fallback = (rule.fallback or "").strip().lower()
    if fallback != "jina":
        return
    logger.info(
        "web-save fallback requested url=%s phase=%s rule=%s fallback=%s",
        url,
        phase,
        rule.id,
        fallback,
    )
    raise LocalParseFallbackError(fallback=fallback, rule_id=rule.id)


def fetch_substack_body_html(
    url: str, html: str, *, timeout: int = 30
) -> tuple[str, dict] | None:
    """Fetch Substack post HTML from the public API when available."""
    parsed = urlparse(url)
    if "/p/" not in parsed.path:
        return None
    slug = parsed.path.split("/p/")[-1].strip("/")
    if not slug:
        return None
    api_url = f"{parsed.scheme}://{parsed.netloc}/api/v1/posts/{slug}"
    response = requests.get(
        api_url, headers={"User-Agent": USER_AGENT}, timeout=timeout
    )
    response.raise_for_status()
    data = response.json()
    body_html = data.get("body_html")
    if not body_html:
        return None
    meta = {
        "title": data.get("title"),
        "author": data.get("author") or data.get("author_name"),
        "published": data.get("post_date") or data.get("published_at"),
        "canonical": data.get("canonical_url"),
    }
    return body_html, meta


class _PreservingMarkdownConverter(MarkdownConverter):
    def convert_mark(self, el, text, parent_tags):
        return f"<mark>{text}</mark>"

    def convert_nav(self, el, text, parent_tags):
        return str(el)

    def convert_svg(self, el, text, parent_tags):
        return str(el)


def html_to_markdown(html: str) -> str:
    """Convert HTML to Markdown."""
    converter = _PreservingMarkdownConverter(heading_style="ATX")
    return converter.convert(html).strip()


def build_frontmatter(markdown_text: str, *, meta: dict) -> str:
    """Build YAML frontmatter + markdown output."""
    payload = {key: value for key, value in meta.items() if value is not None}
    frontmatter = yaml.safe_dump(payload, sort_keys=False, allow_unicode=False).strip()
    return f"---\n{frontmatter}\n---\n\n{markdown_text.strip()}\n"


def parse_url_local(url: str, *, timeout: int = 30) -> ParsedPage:
    """Parse a URL locally into Markdown with frontmatter."""
    start_time = time.monotonic()
    normalized = ensure_url(url)
    logger.info("web-save parse start url=%s", normalized)
    fetch_started_at = time.monotonic()
    html, final_url, used_js_rendering = fetch_html(normalized, timeout=timeout)
    is_initial_tiktok_video = is_tiktok_video_url(final_url)
    html = strip_control_chars(html)
    if rendered := maybe_build_snapshot_render(
        final_url,
        raw_html=html,
        used_js_rendering=used_js_rendering,
        tiktok_fetcher=fetch_tiktok_video_snapshot,
        twitter_fetcher=fetch_twitter_status_snapshot,
        patreon_extractor=extract_patreon_post_snapshot,
    ):
        content = build_frontmatter(rendered.markdown, meta=rendered.meta)
        logger.info(
            "web-save snapshot kind=%s url=%s source=%s markdown_len=%s locked=%s",
            rendered.kind,
            final_url,
            rendered.source,
            len(rendered.markdown),
            rendered.locked,
        )
        return ParsedPage(
            title=rendered.title,
            content=content,
            source=rendered.source,
            published_at=rendered.published_at,
        )
    if not is_initial_tiktok_video:
        raise_antibot_fallback_if_needed(html, stage="direct")
    html, final_url, used_js_rendering = maybe_unwrap_apple_news(
        html=html,
        final_url=final_url,
        used_js_rendering=used_js_rendering,
        timeout=timeout,
        fetch_html=lambda u, t: fetch_html(u, timeout=t),
        logger=logger,
    )
    html = strip_control_chars(html)
    if not is_tiktok_video_url(final_url):
        raise_antibot_fallback_if_needed(html, stage="apple-unwrapped")
    logger.info(
        (
            "web-save fetched url=%s final_url=%s used_js=%s html_len=%s "
            "fetch_elapsed_ms=%s"
        ),
        normalized,
        final_url,
        used_js_rendering,
        len(html),
        int((time.monotonic() - fetch_started_at) * 1000),
    )
    initial_html = html
    initial_url = final_url
    engine = get_rule_engine()
    pre_rules = engine.match_rules(final_url, html, phase="pre")
    if pre_rules:
        logger.debug(
            "web-save pre rules url=%s ids=%s",
            final_url,
            [rule.id for rule in pre_rules],
        )
    render_mode, wait_for, render_timeout = resolve_rendering_settings(pre_rules)
    if not used_js_rendering and render_mode == "force":
        render_started_at = time.monotonic()
        try:
            logger.info(
                "web-save render start url=%s mode=force wait_for=%s timeout_ms=%s",
                final_url,
                wait_for,
                render_timeout,
            )
            html, final_url = render_html_with_playwright(
                final_url, timeout=render_timeout, wait_for=wait_for
            )
            used_js_rendering = True
            html = strip_control_chars(html)
            if not is_tiktok_video_url(final_url):
                raise_antibot_fallback_if_needed(html, stage="render-force")
        except LocalParseFallbackError:
            raise
        except Exception as exc:
            logger.warning(
                "web-save force render skip url=%s err=%s render_elapsed_ms=%s",
                final_url,
                exc,
                int((time.monotonic() - render_started_at) * 1000),
            )
        else:
            logger.info(
                "web-save render done url=%s mode=force render_elapsed_ms=%s",
                final_url,
                int((time.monotonic() - render_started_at) * 1000),
            )
    elif not used_js_rendering and render_mode == "auto":
        wait_until = resolve_auto_render_wait_until(html)
        if wait_until and should_auto_render_url(
            final_url, html, is_playwright_allowed=is_playwright_allowed
        ):
            render_started_at = time.monotonic()
            try:
                render_timeout_ms = (
                    min(render_timeout, 15000)
                    if wait_until == "domcontentloaded"
                    else render_timeout
                )
                logger.info(
                    (
                        "web-save render start url=%s mode=auto wait_for=%s "
                        "wait_until=%s timeout_ms=%s"
                    ),
                    final_url,
                    wait_for,
                    wait_until,
                    render_timeout_ms,
                )
                html, final_url = render_html_with_playwright(
                    final_url,
                    timeout=render_timeout_ms,
                    wait_for=wait_for,
                    wait_until=wait_until,
                )
                used_js_rendering = True
                html = strip_control_chars(html)
                if not is_tiktok_video_url(final_url):
                    raise_antibot_fallback_if_needed(html, stage="render-auto")
            except LocalParseFallbackError:
                raise
            except Exception as exc:
                logger.warning(
                    "web-save auto skip url=%s err=%s render_elapsed_ms=%s",
                    final_url,
                    exc,
                    int((time.monotonic() - render_started_at) * 1000),
                )
            else:
                logger.info(
                    "web-save render done url=%s mode=auto render_elapsed_ms=%s",
                    final_url,
                    int((time.monotonic() - render_started_at) * 1000),
                )

    if html != initial_html or final_url != initial_url:
        pre_rules = engine.match_rules(final_url, html, phase="pre")
        if pre_rules:
            logger.debug(
                "web-save pre rules (post-render) url=%s ids=%s",
                final_url,
                [rule.id for rule in pre_rules],
            )
    logger.info(
        "web-save rendering url=%s mode=%s used_js=%s wait_for=%s timeout_ms=%s",
        final_url,
        render_mode,
        used_js_rendering,
        wait_for,
        render_timeout,
    )

    html = strip_control_chars(html)
    raw_html_original = html
    metadata = extract_metadata(html, final_url)
    favicon_url = resolve_favicon_url(metadata.get("favicon"), final_url)
    if ft_barrier_payload := extract_ft_barrier_payload(raw_html_original, final_url):
        title = ft_barrier_payload.get("title") or metadata.get("title") or final_url
        published_at = parse_datetime(ft_barrier_payload.get("published"))
        preview = (ft_barrier_payload.get("preview") or "").strip()
        body = (
            "Warning: This article appears truncated. Full content may be behind a "
            "paywall."
        )
        if preview:
            body = f"{body}\n\n{preview}"
        content = build_frontmatter(
            body,
            meta={
                "source": metadata.get("canonical") or final_url,
                "title": title,
                "author": ft_barrier_payload.get("author"),
                "published_date": (published_at.isoformat() if published_at else None),
                "domain": urlparse(final_url).netloc,
                "paywalled": True,
                "truncated": bool(preview),
                "used_js_rendering": used_js_rendering,
                "saved_at": datetime.now(UTC).isoformat(),
            },
        )
        return ParsedPage(
            title=title,
            content=content,
            source=metadata.get("canonical") or final_url,
            published_at=published_at,
            favicon_url=favicon_url,
        )
    if pre_rules:
        html = engine.apply_rules(html, pre_rules)
    discard_rule = next((rule for rule in pre_rules if rule.discard), None)
    if discard_rule:
        _raise_fallback_for_discard_rule(
            rule=discard_rule,
            phase="pre",
            url=metadata.get("canonical") or final_url,
        )
        content = _discard_frontmatter(
            source=metadata.get("canonical") or final_url,
            domain=urlparse(final_url).netloc,
            rule=discard_rule,
            used_js_rendering=used_js_rendering,
        )
        return ParsedPage(
            title=metadata.get("title") or urlparse(final_url).netloc,
            content=content,
            source=metadata.get("canonical") or final_url,
            published_at=None,
        )

    if rendered := maybe_build_snapshot_render(
        final_url,
        raw_html=raw_html_original,
        used_js_rendering=used_js_rendering,
        tiktok_fetcher=fetch_tiktok_video_snapshot,
        twitter_fetcher=fetch_twitter_status_snapshot,
        patreon_extractor=extract_patreon_post_snapshot,
    ):
        content = build_frontmatter(rendered.markdown, meta=rendered.meta)
        logger.info(
            "web-save snapshot kind=%s url=%s source=%s markdown_len=%s locked=%s",
            rendered.kind,
            final_url,
            rendered.source,
            len(rendered.markdown),
            rendered.locked,
        )
        return ParsedPage(
            title=rendered.title,
            content=content,
            source=rendered.source,
            published_at=rendered.published_at,
            favicon_url=favicon_url,
        )

    html, pre_youtube_ids = replace_youtube_iframes_with_placeholders(
        html, metadata.get("canonical") or final_url
    )
    raw_dom = _safe_html_tree(html)
    raw_dom_original = _safe_html_tree(raw_html_original)
    pre_dom = _safe_html_tree(html)

    document = ReadabilityDocument(html) if ReadabilityDocument else None
    substack_payload = None
    used_blog_google_ordered_extraction = False
    try:
        substack_payload = fetch_substack_body_html(final_url, html, timeout=timeout)
    except requests.RequestException:
        substack_payload = None
    if substack_payload:
        article_html, substack_meta = substack_payload
        metadata.update({key: value for key, value in substack_meta.items() if value})
        if not is_substack_host(urlparse(final_url).netloc):
            pre_rules = merge_rules(
                pre_rules,
                match_substack_host_rules(engine, html, phase="pre"),
            )
    else:
        if document is None:
            article_html = html
        else:
            try:
                article_html = document.summary(html_partial=True)
            except ValueError as exc:
                logger.warning(
                    "web-save readability failed url=%s error=%s", final_url, exc
                )
                article_html = html
        article_html, domain_metadata, used_blog_google_ordered_extraction = (
            apply_domain_specific_extractor(
                article_html,
                final_url=final_url,
                raw_html=raw_html_original,
            )
        )
        for key, value in domain_metadata.items():
            if value is not None or key == "image":
                metadata[key] = value
    logger.debug(
        "web-save readability url=%s article_len=%s",
        final_url,
        len(article_html),
    )
    post_rules = engine.match_rules(final_url, article_html, phase="post")
    if substack_payload and not is_substack_host(urlparse(final_url).netloc):
        post_rules = merge_rules(
            post_rules,
            match_substack_host_rules(engine, article_html, phase="post"),
        )
    if post_rules:
        logger.debug(
            "web-save post rules url=%s ids=%s",
            final_url,
            [rule.id for rule in post_rules],
        )
        post_tree = _safe_html_tree(article_html)
        post_tree = engine.apply_rules_tree(post_tree, post_rules)
        article_html = _safe_html_tostring(post_tree, article_html)
    discard_rule = next((rule for rule in post_rules if rule.discard), None)
    if discard_rule:
        _raise_fallback_for_discard_rule(
            rule=discard_rule,
            phase="post",
            url=metadata.get("canonical") or final_url,
        )
        content = _discard_frontmatter(
            source=metadata.get("canonical") or final_url,
            domain=urlparse(final_url).netloc,
            rule=discard_rule,
            used_js_rendering=used_js_rendering,
        )
        return ParsedPage(
            title=metadata.get("title") or urlparse(final_url).netloc,
            content=content,
            source=metadata.get("canonical") or final_url,
            published_at=None,
        )
    overrides = extract_metadata_overrides(article_html, post_rules)
    if overrides:
        metadata.update(overrides)
    include_selectors = [
        selector for rule in pre_rules + post_rules for selector in rule.include
    ]
    if used_blog_google_ordered_extraction:
        include_selectors = []
    removal_selectors = [selector for rule in post_rules for selector in rule.remove]
    reinsert_dom = raw_dom
    if any(rule.selector_overrides for rule in pre_rules):
        reinsert_dom = pre_dom
        removal_selectors = [
            selector for rule in pre_rules + post_rules for selector in rule.remove
        ]
    if include_selectors:
        article_html = apply_include_reinsertion(
            article_html,
            reinsert_dom,
            include_selectors,
            removal_selectors,
        )
        logger.debug(
            "web-save include reinsertion url=%s selectors=%s removals=%s",
            final_url,
            len(include_selectors),
            len(removal_selectors),
        )
    domain = urlparse(final_url).netloc
    before_img_count = len(BeautifulSoup(article_html, "html.parser").find_all("img"))
    article_html = filter_non_content_images(article_html, domain=domain)
    after_img_count = len(BeautifulSoup(article_html, "html.parser").find_all("img"))
    logger.debug(
        "web-save images url=%s before=%s after=%s",
        final_url,
        before_img_count,
        after_img_count,
    )
    article_html = polish_article_html(article_html)
    article_html = normalize_image_sources(
        article_html, metadata.get("canonical") or final_url
    )
    article_html = normalize_link_sources(
        article_html, metadata.get("canonical") or final_url
    )
    article_html = normalize_image_captions(article_html)
    article_html = preserve_substack_native_video_embeds(
        article_html,
        raw_html_original,
        source_url=metadata.get("canonical") or final_url,
    )
    article_html = insert_youtube_placeholders(
        article_html, raw_dom_original, metadata.get("canonical") or final_url
    )
    source_url = metadata.get("canonical") or final_url
    title = resolve_website_title(
        metadata.get("title"),
        url=source_url,
        raw_html=raw_html_original,
    )
    if not title:
        title = resolve_website_title(
            document.short_title() or document.title(),
            url=source_url,
            raw_html=raw_html_original,
            allow_network=False,
        )
    if not title:
        title = urlparse(final_url).netloc
    image_url = metadata.get("image")
    if image_url:
        resolved_image = urljoin(source_url, image_url)
        if domain.endswith("wired.com"):
            resolved_image = normalize_wired_image_url(resolved_image)
        article_html = prepend_hero_image(article_html, resolved_image, title)
    markdown = html_to_markdown(article_html)
    if domain.endswith("theverge.com"):
        markdown = simplify_linked_images(markdown)
        markdown = cleanup_verge_markdown(markdown)
    if domain.endswith("forbes.com"):
        markdown = (
            extract_forbes_article_markdown(markdown, source=source_url) or markdown
        )
    if domain.endswith("gizmodo.com"):
        markdown = cleanup_gizmodo_markdown(markdown)
    if domain.endswith("youtube.com"):
        markdown = cleanup_youtube_markdown(markdown, source_url)
    if domain.endswith("openai.com"):
        markdown = cleanup_openai_markdown(markdown)
    if domain.endswith("github.com"):
        markdown = cleanup_github_markdown(markdown)
    if should_apply_substack_cleanup(
        final_url=final_url,
        raw_html=raw_html_original,
        article_html=article_html,
        markdown=markdown,
    ):
        markdown = cleanup_substack_markdown(markdown)
    logger.debug("web-save markdown url=%s len=%s", final_url, len(markdown))
    markdown, embedded_ids = replace_youtube_placeholders(markdown)
    embedded_ids = embedded_ids.union(pre_youtube_ids)
    jsonld_anchors, jsonld_ids = extract_youtube_anchors_from_jsonld(raw_html_original)
    anchors = _merge_youtube_anchors(
        jsonld_anchors,
        build_youtube_anchor_map(
            raw_dom_original, metadata.get("canonical") or final_url
        ),
    )
    if jsonld_ids:
        logger.debug(
            "web-save youtube jsonld url=%s ids=%s",
            final_url,
            sorted(jsonld_ids),
        )
    if anchors:
        markdown, anchored_ids = insert_youtube_after_anchors(markdown, anchors)
        embedded_ids = embedded_ids.union(anchored_ids)
        logger.debug(
            "web-save youtube anchors url=%s anchors=%s inserted=%s",
            final_url,
            len(anchors),
            len(anchored_ids),
        )
    if not markdown:
        if is_paywalled(html, domain) or is_paywalled(article_html, domain):
            preview_markdown = extract_paywall_preview_markdown(
                article_html=article_html,
                raw_html=raw_html_original,
            )
            anti_bot_blocked = is_anti_bot_challenge_page(
                html
            ) or is_anti_bot_challenge_page(raw_html_original)
            content = build_paywall_frontmatter(
                source=metadata.get("canonical") or final_url,
                domain=domain,
                used_js_rendering=used_js_rendering,
                preview_markdown=preview_markdown,
                anti_bot_blocked=anti_bot_blocked,
            )
            title = (
                metadata.get("title")
                or document.short_title()
                or document.title()
                or urlparse(final_url).netloc
            )
            return ParsedPage(
                title=title,
                content=content,
                source=metadata.get("canonical") or final_url,
                published_at=None,
            )
        raise ValueError("No readable content extracted")

    published_at = parse_datetime(metadata.get("published"))
    domain = urlparse(final_url).netloc

    embeds = extract_youtube_embed_urls_from_dom(
        raw_dom_original, metadata.get("canonical") or final_url
    )
    if not embeds and not embedded_ids:
        if jsonld_ids:
            embeds = [
                f"https://www.youtube.com/watch?v={video_id}"
                for video_id in sorted(jsonld_ids)
            ]
        else:
            if not domain.endswith("theverge.com"):
                script_ids = extract_youtube_video_ids_from_html(
                    raw_html_original, metadata.get("canonical") or final_url
                )
                if script_ids:
                    embeds = [f"https://www.youtube.com/watch?v={script_ids[0]}"]
    if embeds:
        existing = markdown
        lines = []
        for embed_url in embeds:
            video_id = extract_youtube_video_id(embed_url)
            if video_id and video_id in embedded_ids:
                continue
            if embed_url in existing:
                continue
            lines.append(f"[YouTube]({embed_url})")
        if lines:
            cookie_marker = "content isn't visible due to your cookie preferences"
            if cookie_marker in markdown:
                split_lines = markdown.splitlines()
                for idx, line in enumerate(split_lines):
                    if cookie_marker in line.lower():
                        insertion_index = idx + 1
                        for offset, link in enumerate(lines):
                            split_lines.insert(insertion_index + offset, link)
                        markdown = "\n".join(split_lines)
                        break
                else:
                    markdown = f"{markdown}\n\n" + "\n".join(lines)
            else:
                markdown = f"{markdown}\n\n" + "\n".join(lines)
        logger.debug(
            "web-save youtube fallback url=%s added=%s",
            final_url,
            len(lines),
        )

    markdown = dedupe_markdown_images(markdown)
    markdown = wrap_gallery_blocks(markdown)
    if domain.endswith("github.com"):
        # Final safety pass after markdown post-processing.
        markdown = cleanup_github_markdown(markdown)
    markdown = dedupe_markdown_blocks(markdown)
    gallery_blocks = markdown.count('class="image-gallery"')
    logger.info(
        "web-save postprocess url=%s markdown_len=%s galleries=%s elapsed_ms=%s",
        final_url,
        len(markdown),
        gallery_blocks,
        int((time.monotonic() - start_time) * 1000),
    )
    wsj_result = maybe_enrich_wsj_preview(
        domain=domain,
        final_url=final_url,
        source_url=source_url,
        raw_html=raw_html_original,
        markdown=markdown,
        title=title,
    )
    markdown, source_url, title, published_override, wsj_flags = wsj_result
    if published_override:
        metadata["published"] = published_override
        published_at = parse_datetime(published_override)
    metadata["canonical"] = source_url
    word_count = compute_word_count(markdown)
    image_count = count_images(markdown)
    tags = extract_tags(markdown, domain, title)

    frontmatter_meta = {
        "source": source_url,
        "title": title,
        "author": metadata.get("author"),
        "published_date": published_at.isoformat() if published_at else None,
        "domain": domain,
        "word_count": word_count,
        "reading_time": page_reading_time(
            word_count, image_count, domain, raw_html_original
        ),
        "tags": tags,
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(UTC).isoformat(),
    }
    frontmatter_meta.update({key: value for key, value in wsj_flags.items() if value})

    content = build_frontmatter(markdown, meta=frontmatter_meta)

    return ParsedPage(
        title=title,
        content=content,
        source=source_url,
        published_at=published_at,
        favicon_url=favicon_url,
    )


@lru_cache(maxsize=1)
def get_rule_engine() -> RuleEngine:
    """Return the cached rule engine for web-save parsing."""
    return RuleEngine.from_rules_dir(RULES_DIR)


@lru_cache(maxsize=1)
def get_playwright_allowlist() -> set[str]:
    """Return the cached Playwright allowlist host set."""
    if not PLAYWRIGHT_ALLOWLIST_PATH.exists():
        return set()
    payload = yaml.safe_load(PLAYWRIGHT_ALLOWLIST_PATH.read_text()) or []
    if isinstance(payload, list):
        return {str(item).strip().lower() for item in payload if str(item).strip()}
    return set()


def is_playwright_allowed(url: str) -> bool:
    """Return True if Playwright rendering is allowed for the URL."""
    host = urlparse(url).netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    if not host:
        return False
    allowlist = get_playwright_allowlist()
    return any(host == domain or host.endswith(f".{domain}") for domain in allowlist)
