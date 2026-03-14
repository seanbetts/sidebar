"""Rendering helpers for web-save parsing."""

from __future__ import annotations

import os
from pathlib import Path

from api.services.web_save_constants import USER_AGENT
from api.services.web_save_rules import Rule

_DEFAULT_PLAYWRIGHT_BROWSERS_PATH = Path("/ms-playwright")


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

    with sync_playwright() as playwright:
        try:
            browser = playwright.chromium.launch(headless=True, channel="chrome")
        except Exception:
            browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(user_agent=USER_AGENT)
        page = context.new_page()
        try:
            page.goto(url, wait_until=wait_until, timeout=timeout)
        except PlaywrightTimeoutError:
            if wait_until != "domcontentloaded":
                page.goto(url, wait_until="domcontentloaded", timeout=timeout)
            else:
                raise
        if wait_for:
            page.wait_for_selector(wait_for, timeout=timeout)
        html = page.content()
        final_url = page.url
        browser.close()
    return html, final_url


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
