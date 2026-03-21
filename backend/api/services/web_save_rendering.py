"""Rendering helpers for web-save parsing."""

from __future__ import annotations

import os
import threading
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urlparse

from api.config import settings
from api.services.web_save_antibot import AntibotDetection, detect_antibot_html
from api.services.web_save_constants import USER_AGENT
from api.services.web_save_rules import Rule

_DEFAULT_PLAYWRIGHT_BROWSERS_PATH = Path("/ms-playwright")
_PLAYWRIGHT_RENDER_SEMAPHORE_LOCK = threading.Lock()
_playwright_render_limit: int | None = None
_playwright_render_semaphore: threading.BoundedSemaphore | None = None


@dataclass(frozen=True)
class RenderedPageClassification:
    """Classification results for a rendered page snapshot."""

    title: str | None
    html: str
    antibot_detection: AntibotDetection | None


class RenderedPage(Protocol):
    """Minimal interface required to summarize a rendered page."""

    def content(self) -> str:
        """Return the rendered HTML."""
        ...

    def title(self) -> str:
        """Return the rendered document title."""
        ...


def classify_rendered_html(
    html: str,
    title: str | None = None,
) -> AntibotDetection | None:
    """Return any anti-bot detection for the rendered markup plus title."""
    combined = f"<title>{title}</title>{html}" if title else html
    return detect_antibot_html(combined)


def summarize_rendered_page(page: RenderedPage) -> RenderedPageClassification:
    """Capture the rendered title, HTML, and anti-bot classification."""
    html = page.content()
    title = page.title()
    return RenderedPageClassification(
        title=title,
        html=html,
        antibot_detection=classify_rendered_html(html, title=title),
    )


def requires_js_rendering(html: str) -> bool:
    """Detect if the page likely requires JS rendering."""
    if len(html) < 500:
        return True
    if "youtube.com/embed" in html and "<iframe" not in html:
        return True

    markers = ("react-root", "ng-app", "__NEXT_DATA__", "nuxt", "__gatsby")
    return any(marker in html for marker in markers)


def has_unrendered_youtube_embed(html: str) -> bool:
    """Return True when a YouTube embed likely needs JS rendering."""
    return "youtube.com/embed" in html and "<iframe" not in html


def has_unrendered_substack_native_video(html: str) -> bool:
    """Return True when a Substack native video placeholder lacks a hydrated player."""
    lowered = html.lower()
    has_placeholder = (
        'data-component-name="videoembedplayer"' in lowered
        or 'data-component-name="videoplaceholder"' in lowered
        or 'class="native-video-embed"' in lowered
    )
    return has_placeholder and "<video" not in lowered


def configure_playwright_browsers_path(
    *,
    default_path: Path = _DEFAULT_PLAYWRIGHT_BROWSERS_PATH,
) -> str | None:
    """Prefer the shared Playwright browser install when available."""
    current_path = os.environ.get("PLAYWRIGHT_BROWSERS_PATH")
    if current_path:
        return current_path

    if default_path.exists():
        resolved = str(default_path)
        os.environ["PLAYWRIGHT_BROWSERS_PATH"] = resolved
        return resolved

    return None


def _get_playwright_render_semaphore() -> threading.BoundedSemaphore:
    """Return a process-wide semaphore for Playwright-backed renders."""
    global _playwright_render_limit, _playwright_render_semaphore

    limit = max(1, settings.playwright_render_concurrency)
    with _PLAYWRIGHT_RENDER_SEMAPHORE_LOCK:
        if _playwright_render_semaphore is None or _playwright_render_limit != limit:
            _playwright_render_limit = limit
            _playwright_render_semaphore = threading.BoundedSemaphore(limit)
        return _playwright_render_semaphore


@contextmanager
def limit_playwright_renders():
    """Serialize heavyweight Playwright renders within the worker process."""
    semaphore = _get_playwright_render_semaphore()
    semaphore.acquire()
    try:
        yield
    finally:
        semaphore.release()


def resolve_auto_render_wait_until(html: str) -> str | None:
    """Return the Playwright wait mode for special auto-render cases."""
    if has_unrendered_substack_native_video(html):
        return "networkidle"
    if has_unrendered_youtube_embed(html):
        return "domcontentloaded"
    if requires_js_rendering(html):
        return "networkidle"
    return None


def should_auto_render_url(url: str, html: str, *, is_playwright_allowed) -> bool:
    """Return whether auto-rendering should run for the current page."""
    host = urlparse(url).netloc.lower().strip(".")
    if host.startswith("www."):
        host = host[4:]

    # Verge article pages already expose parseable body components in the
    # initial HTML, so forcing Playwright on raw YouTube embed markers only
    # adds latency without improving extraction quality.
    if (
        host.endswith("theverge.com")
        and "duet--article--article-body-component" in html.lower()
    ):
        return False

    if has_unrendered_youtube_embed(html) or has_unrendered_substack_native_video(html):
        return True
    return resolve_auto_render_wait_until(html) is not None and is_playwright_allowed(
        url
    )


def render_html_with_playwright(
    url: str,
    *,
    timeout: int = 30000,
    wait_for: str | None = None,
    wait_until: str = "networkidle",
) -> tuple[str, str]:
    """Render HTML using Playwright for JS-heavy pages."""
    configure_playwright_browsers_path()
    try:
        from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
        from playwright.sync_api import sync_playwright
    except ImportError as exc:  # pragma: no cover - depends on optional dependency
        raise RuntimeError("Playwright is not installed") from exc

    with limit_playwright_renders(), sync_playwright() as playwright:
        try:
            browser = playwright.chromium.launch(headless=True, channel="chrome")
        except Exception:
            browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(user_agent=USER_AGENT)
        page = context.new_page()
        should_close_browser = True
        try:
            page.goto(url, wait_until=wait_until, timeout=timeout)
            preview = summarize_rendered_page(page)
            final_url = page.url
            if preview.antibot_detection:
                return preview.html, final_url
            if wait_for:
                page.wait_for_selector(wait_for, timeout=timeout)
            html = page.content()
            final_url = page.url
            return html, final_url
        except PlaywrightTimeoutError:
            # Let the outer sync_playwright() teardown stop the driver session
            # directly. Explicit browser.close() can take much longer than the
            # navigation timeout on timed-out pages.
            should_close_browser = False
            raise
        finally:
            if should_close_browser:
                browser.close()


def resolve_rendering_settings(rules: list[Rule]) -> tuple[str, str | None, int]:
    """Resolve rendering settings from matched rules."""
    mode = "auto"
    wait_for = None
    timeout = 30000
    for rule in rules:
        rendering = rule.rendering or {}
        rule_mode = rendering.get("mode", "auto")
        if rule_mode == "force":
            mode = "force"
            wait_for = rendering.get("wait_for", wait_for)
            timeout = rendering.get("timeout", timeout)
        elif rule_mode == "never" and mode != "force":
            mode = "never"
        elif rule_mode == "auto" and mode not in {"force", "never"}:
            mode = "auto"
        if mode != "force":
            wait_for = rendering.get("wait_for", wait_for)
            timeout = rendering.get("timeout", timeout)
    return mode, wait_for, timeout
