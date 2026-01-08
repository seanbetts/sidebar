"""Local parsing utilities for the web-save skill."""

from __future__ import annotations

import logging
import re
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
from readability import Document

from api.services.web_save_constants import USER_AGENT
from api.services.web_save_includes import apply_include_reinsertion
from api.services.web_save_parser_cleanup import (
    cleanup_gizmodo_markdown,
    cleanup_openai_markdown,
    cleanup_verge_markdown,
    cleanup_youtube_markdown,
    dedupe_markdown_images,
    extract_openai_body_html,
    filter_non_content_images,
    is_paywalled,
    normalize_image_captions,
    normalize_image_sources,
    normalize_link_sources,
    polish_article_html,
    prepend_hero_image,
    simplify_linked_images,
    wrap_gallery_blocks,
)
from api.services.web_save_parser_html import _safe_html_tostring, _safe_html_tree
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
    has_unrendered_youtube_embed,
    render_html_with_playwright,
    requires_js_rendering,
    resolve_rendering_settings,
)
from api.services.web_save_rules import Rule, RuleEngine, extract_metadata_overrides
from api.services.web_save_tagger import (
    calculate_reading_time,
    compute_word_count,
    extract_tags,
)

logger = logging.getLogger(__name__)

RULES_DIR = Path(__file__).resolve().parents[2] / "skills" / "web-save" / "rules"
PLAYWRIGHT_ALLOWLIST_PATH = RULES_DIR / "playwright_allowlist.yaml"
CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]")


@dataclass(frozen=True)
class ParsedPage:
    """Parsed page payload for saving."""

    title: str
    content: str
    source: str
    published_at: datetime | None


def ensure_url(value: str) -> str:
    """Ensure URL has a scheme."""
    if value.startswith(("http://", "https://")):
        return value
    return f"https://{value}"


def strip_control_chars(value: str) -> str:
    """Strip non-XML control characters that break lxml/readability."""
    if not value:
        return value
    return CONTROL_CHARS_RE.sub("", value)


def fetch_html(url: str, *, timeout: int = 30) -> tuple[str, str, bool]:
    """Fetch raw HTML and return (html, final_url, used_js_rendering)."""
    headers = {"User-Agent": USER_AGENT}
    try:
        response = requests.get(url, headers=headers, timeout=timeout)
        response.raise_for_status()
        return response.text, str(response.url), False
    except requests.HTTPError as exc:
        status_code = None
        if exc.response is not None:
            status_code = exc.response.status_code
        if status_code in {401, 403, 429}:
            html, final_url = render_html_with_playwright(
                url,
                timeout=timeout * 1000,
                wait_until="domcontentloaded",
            )
            return html, final_url, True
        raise


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


def _paywall_frontmatter(
    *,
    source: str,
    domain: str,
    used_js_rendering: bool,
) -> str:
    frontmatter_meta = {
        "source": source,
        "domain": domain,
        "discarded": True,
        "paywalled": True,
        "discard_reason": "Paywall detected",
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(UTC).isoformat(),
    }
    return build_frontmatter(
        "Unable to save content. This site appears to be behind a paywall.",
        meta=frontmatter_meta,
    )


def extract_metadata(html: str, url: str) -> dict:
    """Extract basic metadata from HTML."""
    soup = BeautifulSoup(html, "html.parser")

    def find_meta(names: list[str], attrs: tuple[str, ...]) -> str | None:
        for name in names:
            for attr in attrs:
                tag = soup.find("meta", attrs={attr: name})
                if tag and tag.get("content"):
                    return tag["content"].strip()
        return None

    title = find_meta(["og:title", "twitter:title"], ("property", "name")) or (
        soup.title.string.strip() if soup.title and soup.title.string else None
    )
    author = find_meta(
        ["author", "article:author", "parsely-author"], ("name", "property")
    )
    published = find_meta(
        ["article:published_time", "og:pubdate", "pubdate", "date", "parsely-pub-date"],
        ("property", "name"),
    )
    image = find_meta(["og:image", "twitter:image"], ("property", "name"))

    canonical = None
    canonical_tag = soup.find("link", rel="canonical")
    if canonical_tag and canonical_tag.get("href"):
        canonical = canonical_tag["href"].strip()

    return {
        "title": title,
        "author": author,
        "published": published,
        "canonical": canonical or url,
        "image": image,
    }


def fetch_substack_body_html(
    url: str, html: str, *, timeout: int = 30
) -> tuple[str, dict] | None:
    """Fetch Substack post HTML from the public API when available."""
    if "substack" not in html.lower():
        return None
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


def parse_datetime(value: str | None) -> datetime | None:
    """Parse ISO-like datetime strings."""
    if not value:
        return None
    cleaned = value.strip()
    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


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
    html, final_url, used_js_rendering = fetch_html(normalized, timeout=timeout)
    html = strip_control_chars(html)
    logger.info(
        "web-save fetched url=%s final_url=%s used_js=%s html_len=%s",
        normalized,
        final_url,
        used_js_rendering,
        len(html),
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
    if used_js_rendering:
        pass
    elif render_mode == "force":
        html, final_url = render_html_with_playwright(
            final_url, timeout=render_timeout, wait_for=wait_for
        )
        used_js_rendering = True
    elif render_mode == "auto" and requires_js_rendering(html):
        unrendered_embed = has_unrendered_youtube_embed(html)
        allow_render = is_playwright_allowed(final_url) or unrendered_embed
        if allow_render:
            try:
                if unrendered_embed:
                    html, final_url = render_html_with_playwright(
                        final_url,
                        timeout=min(render_timeout, 15000),
                        wait_for=wait_for,
                        wait_until="domcontentloaded",
                    )
                else:
                    html, final_url = render_html_with_playwright(
                        final_url, timeout=render_timeout, wait_for=wait_for
                    )
                used_js_rendering = True
            except RuntimeError:
                pass

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
    if pre_rules:
        html = engine.apply_rules(html, pre_rules)
    discard_rule = next((rule for rule in pre_rules if rule.discard), None)
    if discard_rule:
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

    html, pre_youtube_ids = replace_youtube_iframes_with_placeholders(
        html, metadata.get("canonical") or final_url
    )
    raw_dom = _safe_html_tree(html)
    raw_dom_original = _safe_html_tree(raw_html_original)
    pre_dom = _safe_html_tree(html)

    document = Document(html)
    substack_payload = None
    try:
        substack_payload = fetch_substack_body_html(final_url, html, timeout=timeout)
    except requests.RequestException:
        substack_payload = None
    if substack_payload:
        article_html, substack_meta = substack_payload
        metadata.update({key: value for key, value in substack_meta.items() if value})
    else:
        try:
            article_html = document.summary(html_partial=True)
        except ValueError as exc:
            logger.warning(
                "web-save readability failed url=%s error=%s", final_url, exc
            )
            article_html = html
        if urlparse(final_url).netloc.endswith("openai.com"):
            openai_html = extract_openai_body_html(raw_html_original)
            if openai_html:
                article_html = openai_html
    logger.debug(
        "web-save readability url=%s article_len=%s",
        final_url,
        len(article_html),
    )
    post_rules = engine.match_rules(final_url, article_html, phase="post")
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
    article_html = insert_youtube_placeholders(
        article_html, raw_dom_original, metadata.get("canonical") or final_url
    )
    title = (
        metadata.get("title")
        or document.short_title()
        or document.title()
        or urlparse(final_url).netloc
    )
    source_url = metadata.get("canonical") or final_url
    image_url = metadata.get("image")
    if image_url:
        resolved_image = urljoin(source_url, image_url)
        article_html = prepend_hero_image(article_html, resolved_image, title)
    markdown = html_to_markdown(article_html)
    if domain.endswith("theverge.com"):
        markdown = simplify_linked_images(markdown)
        markdown = cleanup_verge_markdown(markdown)
    if domain.endswith("gizmodo.com"):
        markdown = cleanup_gizmodo_markdown(markdown)
    if domain.endswith("youtube.com"):
        markdown = cleanup_youtube_markdown(markdown, source_url)
    if domain.endswith("openai.com"):
        markdown = cleanup_openai_markdown(markdown)
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
        domain = urlparse(final_url).netloc
        if is_paywalled(html, domain) or is_paywalled(article_html, domain):
            content = _paywall_frontmatter(
                source=metadata.get("canonical") or final_url,
                domain=domain,
                used_js_rendering=used_js_rendering,
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
    word_count = compute_word_count(markdown)
    domain = urlparse(final_url).netloc
    tags = extract_tags(markdown, domain, title)
    source_url = metadata.get("canonical") or final_url

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
    gallery_blocks = markdown.count('class="image-gallery"')
    logger.info(
        "web-save postprocess url=%s markdown_len=%s galleries=%s elapsed_ms=%s",
        final_url,
        len(markdown),
        gallery_blocks,
        int((time.monotonic() - start_time) * 1000),
    )

    frontmatter_meta = {
        "source": metadata.get("canonical") or final_url,
        "title": title,
        "author": metadata.get("author"),
        "published_date": published_at.isoformat() if published_at else None,
        "domain": domain,
        "word_count": word_count,
        "reading_time": calculate_reading_time(word_count),
        "tags": tags,
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(UTC).isoformat(),
    }

    content = build_frontmatter(markdown, meta=frontmatter_meta)

    return ParsedPage(
        title=title,
        content=content,
        source=metadata.get("canonical") or final_url,
        published_at=published_at,
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
