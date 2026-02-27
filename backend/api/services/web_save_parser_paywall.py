"""Paywall-related helpers for the local web-save parser."""

from __future__ import annotations

from datetime import UTC, datetime

import yaml
from bs4 import BeautifulSoup


def build_paywall_frontmatter(
    *,
    source: str,
    domain: str,
    used_js_rendering: bool,
    preview_markdown: str | None = None,
    anti_bot_blocked: bool = False,
) -> str:
    """Build paywall frontmatter and include preview text when available."""
    preview_text = (preview_markdown or "").strip()
    is_truncated = bool(preview_text)
    frontmatter_meta = {
        "source": source,
        "domain": domain,
        "discarded": True,
        "paywalled": True,
        "truncated": is_truncated,
        "anti_bot_blocked": anti_bot_blocked,
        "discard_reason": "Paywall detected",
        "used_js_rendering": used_js_rendering,
        "saved_at": datetime.now(UTC).isoformat(),
    }
    if preview_text:
        body = (
            "Warning: This article appears truncated. Full content may be behind a "
            "paywall.\n\n"
            f"{preview_text}"
        )
    elif anti_bot_blocked:
        body = (
            "Unable to save readable article content. Access appears blocked by an "
            "anti-bot challenge page and may also be paywalled."
        )
    else:
        body = "Unable to save content. This site appears to be behind a paywall."

    payload = {
        key: value for key, value in frontmatter_meta.items() if value is not None
    }
    frontmatter = yaml.safe_dump(payload, sort_keys=False, allow_unicode=False).strip()
    return f"---\n{frontmatter}\n---\n\n{body.strip()}\n"


def is_anti_bot_challenge_page(html_text: str) -> bool:
    """Return True when HTML resembles a bot challenge page."""
    lowered = (html_text or "").lower()
    markers = (
        "captcha-delivery.com",
        "datadome",
        "captcha",
        "please enable js and disable any ad blocker",
        "cf-chl",
    )
    return any(marker in lowered for marker in markers)


def extract_paywall_preview_markdown(*, article_html: str, raw_html: str) -> str:
    """Extract a best-effort preview text from paywalled HTML fragments."""
    skip_tokens = (
        "subscribe",
        "subscription",
        "sign in",
        "log in",
        "account required",
        "enable js",
        "ad blocker",
        "captcha",
        "datadome",
    )
    selectors = ("article", "main", "body")
    fragments = (article_html, raw_html)
    for fragment in fragments:
        if not fragment:
            continue
        soup = BeautifulSoup(fragment, "html.parser")
        for tag in soup(["script", "style", "noscript", "svg", "iframe"]):
            tag.decompose()
        roots = []
        for selector in selectors:
            root = soup.select_one(selector)
            if root is not None:
                roots.append(root)
        if not roots:
            roots = [soup]

        lines: list[str] = []
        seen: set[str] = set()
        for root in roots:
            for node in root.select("h1, h2, h3, p, li, blockquote"):
                text = " ".join(node.get_text(" ", strip=True).split())
                if len(text.split()) < 8:
                    continue
                lowered = text.lower()
                if any(token in lowered for token in skip_tokens):
                    continue
                if text in seen:
                    continue
                seen.add(text)
                lines.append(text)
                if len(" ".join(lines).split()) >= 220:
                    break
            if lines:
                break
        preview = "\n\n".join(lines).strip()
        if preview:
            return preview
    return ""
