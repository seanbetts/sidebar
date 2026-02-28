"""Jina reader helper for website quick saves."""

from __future__ import annotations

import logging
import re
from datetime import datetime
from urllib.parse import urlparse

import httpx

from api.config import settings
from api.services.website_title_service import resolve_website_title

logger = logging.getLogger(__name__)


class JinaFetchError(RuntimeError):
    """Raised when Jina Reader fetch attempts fail."""

    def __init__(
        self,
        message: str,
        *,
        auth_status_code: int | None = None,
        anonymous_status_code: int | None = None,
    ):
        """Initialize fetch error context for authenticated/anonymous attempts."""
        super().__init__(message)
        self.auth_status_code = auth_status_code
        self.anonymous_status_code = anonymous_status_code


class JinaService:
    """Fetch and parse markdown content from Jina Reader API."""

    _ANON_FALLBACK_STATUS_CODES = {401, 402, 403, 451}

    @staticmethod
    def _clean_metadata_value(value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            return None
        if cleaned.lower() in {"undefined", "null", "none", "n/a"}:
            return None
        return cleaned

    @staticmethod
    def fetch_markdown(url: str) -> str:
        """Fetch markdown content for a URL using Jina Reader."""
        if not settings.jina_api_key:
            raise ValueError("JINA_API_KEY is not configured")

        jina_url = f"https://r.jina.ai/{url}"
        headers = {"Authorization": f"Bearer {settings.jina_api_key}"}

        with httpx.Client(timeout=30.0) as client:
            try:
                response = client.get(jina_url, headers=headers)
                response.raise_for_status()
                return response.text
            except httpx.HTTPStatusError as auth_exc:
                auth_status = auth_exc.response.status_code
                if auth_status not in JinaService._ANON_FALLBACK_STATUS_CODES:
                    raise JinaFetchError(
                        (f"Failed to fetch content from Jina.ai: {auth_exc}"),
                        auth_status_code=auth_status,
                    ) from auth_exc

                logger.info(
                    "jina auth request failed status=%s url=%s mode=retry-anonymous",
                    auth_status,
                    url,
                )
                try:
                    anon_response = client.get(jina_url)
                    anon_response.raise_for_status()
                    return anon_response.text
                except httpx.HTTPStatusError as anon_exc:
                    raise JinaFetchError(
                        (
                            "Failed to fetch content from Jina.ai: "
                            f"authenticated request returned {auth_status} and "
                            "anonymous fallback failed: "
                            f"{anon_exc}"
                        ),
                        auth_status_code=auth_status,
                        anonymous_status_code=anon_exc.response.status_code,
                    ) from anon_exc
                except httpx.HTTPError as anon_exc:
                    raise JinaFetchError(
                        (
                            "Failed to fetch content from Jina.ai: "
                            f"authenticated request returned {auth_status} and "
                            "anonymous fallback failed: "
                            f"{anon_exc}"
                        ),
                        auth_status_code=auth_status,
                    ) from anon_exc
            except httpx.HTTPError as exc:
                raise JinaFetchError(
                    f"Failed to fetch content from Jina.ai: {exc}"
                ) from exc

    @staticmethod
    def parse_metadata(markdown: str) -> tuple[dict[str, str | None], str]:
        """Extract Jina metadata and return cleaned markdown."""
        metadata: dict[str, str | None] = {
            "title": None,
            "url_source": None,
            "published_time": None,
            "reading_time": None,
        }

        title_match = re.search(r"^Title:\s*(.+)$", markdown, re.MULTILINE)
        if title_match:
            metadata["title"] = JinaService._clean_metadata_value(title_match.group(1))

        url_match = re.search(r"^URL Source:\s*(.+)$", markdown, re.MULTILINE)
        if url_match:
            metadata["url_source"] = JinaService._clean_metadata_value(
                url_match.group(1)
            )

        published_match = re.search(r"^Published Time:\s*(.+)$", markdown, re.MULTILINE)
        if published_match:
            metadata["published_time"] = JinaService._clean_metadata_value(
                published_match.group(1)
            )
        reading_time_match = re.search(
            r"^Reading Time:\s*(.+)$", markdown, re.MULTILINE
        )
        if reading_time_match:
            metadata["reading_time"] = JinaService._clean_metadata_value(
                reading_time_match.group(1)
            )

        cleaned = markdown
        cleaned = re.sub(r"^Title:.*\n?", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"^URL Source:.*\n?", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"^Published Time:.*\n?", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"^Reading Time:.*\n?", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"^Markdown Content:\s*", "", cleaned, flags=re.MULTILINE)
        cleaned = cleaned.lstrip()

        return metadata, cleaned

    @staticmethod
    def clean_markdown_for_source(markdown: str, source_url: str) -> str:
        """Apply source-specific markdown cleanup for Jina output."""
        if not markdown:
            return markdown
        domain = urlparse(source_url).netloc.lower().strip(".")
        cleaned = markdown
        if domain == "wsj.com" or domain.endswith(".wsj.com"):
            cleaned = JinaService._cleanup_wsj_markdown(cleaned)
        return cleaned.strip()

    @staticmethod
    def _cleanup_wsj_markdown(markdown: str) -> str:
        """Remove WSJ nav/footer/tracker clutter from Jina markdown."""
        cleaned = markdown
        cleaned = re.sub(
            r"(?m)^Warning: This is a cached snapshot of the original page.*\n?",
            "",
            cleaned,
        )
        cleaned = re.sub(
            r"(?m)^!\[[^\]]*]\(blob:http://localhost/[^)]+\)\n?",
            "",
            cleaned,
        )

        heading_matches = list(re.finditer(r"(?m)^.+\n={3,}\n", cleaned))
        article_start = None
        for match in reversed(heading_matches):
            window = cleaned[match.end() : match.end() + 2500]
            if re.search(r"(?m)^By\s*$", window) and re.search(r"\bET\b", window):
                article_start = match.start()
                break
        if article_start is not None:
            cleaned = cleaned[article_start:]

        cleaned = re.sub(
            r"(?m)^Continue reading your article with\s*$\n?",
            "",
            cleaned,
        )
        cleaned = re.sub(r"(?m)^a WSJ subscription\s*$\n?", "", cleaned)
        cleaned = re.sub(r"(?m)^Advertisement\s*$\n?", "", cleaned)
        cleaned = re.sub(
            r"(?m)^Already a subscriber\?\s*\[Sign In]\([^)]+\)\s*$\n?",
            "",
            cleaned,
        )
        cleaned = re.sub(
            r"(?m)^\[Subscribe(?: Now)?]\([^)]+\)\s*$\n?",
            "",
            cleaned,
        )
        cleaned = re.sub(
            (
                r"(?mi)^Reviews and recommendations, independent of "
                r"The Wall Street Journal newsroom\.\s*$\n?"
            ),
            "",
            cleaned,
        )
        cleaned = re.sub(
            r"(?m)^\[Sign In]\(https?://www\.wsj\.com/client/login\?target=[^)]+\)\s*$\n?",
            "",
            cleaned,
        )
        cleaned = re.sub(
            (
                r"(?m)^This copy is for your personal, non-commercial use only\."
                r"[^\n]*\n?"
            ),
            "",
            cleaned,
        )

        cleaned = re.sub(
            r"(?m)^!\[[^\]]*]\(https?://(?:analytics\.twitter\.com|t\.co/1/i/adsct|bat\.bing\.com|sync\.intentiq\.com)[^)]+\)\s*",
            "",
            cleaned,
        )
        cleaned = re.sub(
            r"!\[[^\]]*]\(https?://(?:analytics\.twitter\.com|t\.co/1/i/adsct|bat\.bing\.com|sync\.intentiq\.com)[^)]+\)",
            "",
            cleaned,
        )
        cleaned = re.sub(
            r"(?m)^\[\d+]\(https?://www\.wsj\.com/[^)]*#comments_sector\)\s*$\n?",
            "",
            cleaned,
        )
        cleaned = re.sub(
            (
                r"(?m)^Copyright ©\d{4} Dow Jones & Company, Inc\. "
                r"All Rights Reserved\.[^\n]*\n?"
            ),
            "",
            cleaned,
        )
        cleaned = re.sub(
            r"(?m)^!\[[^\]]*The Wall Street Journal[^\]]*]\(https?://[^)]+\)\s*$\n?",
            "",
            cleaned,
        )
        cleaned = JinaService._trim_wsj_footer(cleaned)
        cleaned = JinaService._filter_wsj_navigation_blocks(cleaned)
        cleaned = re.sub(r"(?m)^\d+\.\s+WSJ\..*\n?", "", cleaned)
        cleaned = re.sub(
            r"(?m)^(Share|Resize|Listen|\(\d+\s+min\))\s*$\n?",
            "",
            cleaned,
        )
        cleaned = re.sub(
            (
                r"(?m)^\*\s+English Edition(?:\s+Edition)?\s+Use Alt \+ Down Arrow "
                r"to expand\.\s*$\n?"
            ),
            "",
            cleaned,
        )
        cleaned = re.sub(r"(?m)^\*\s+\*\s+\*\s*$\n?", "", cleaned)
        cleaned = JinaService._dedupe_wsj_paragraphs(cleaned)
        cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
        return cleaned.strip()

    @staticmethod
    def _trim_wsj_footer(markdown: str) -> str:
        """Trim WSJ footer/legal sections when a footer marker cluster is detected."""
        lines = markdown.splitlines()
        marker_tokens = (
            "[the wall street journal](https://www.wsj.com/)",
            "[subscription options](https://subscribe.wsj.com/membership",
            "[privacy notice](https://www.dowjones.com/privacy-notice",
            "this copy is for your personal, non-commercial use only.",
            "[sign in](https://www.wsj.com/client/login?target=",
        )
        indicator_tokens = (
            "subscribe.wsj.com",
            "customercenter.wsj.com",
            "corporate.wsj.com",
            "wsj.jobs",
            "djreprints.com",
            "dowjones.com/privacy-notice",
            "wsj.com/policy/legal-policies",
            "dowjones.com/terms-of-use",
            "back to top",
            "copyright ©",
        )
        for idx, raw_line in enumerate(lines):
            line = raw_line.strip().lower()
            if not line:
                continue
            if not any(token in line for token in marker_tokens):
                continue
            window = "\n".join(lines[idx : idx + 25]).lower()
            signal_count = sum(token in window for token in indicator_tokens)
            if signal_count >= 2:
                return "\n".join(lines[:idx]).strip()
        return markdown

    @staticmethod
    def _dedupe_wsj_paragraphs(markdown: str) -> str:
        """Remove duplicate long paragraphs while preserving first occurrence order."""
        if not markdown.strip():
            return markdown
        seen: set[str] = set()
        deduped: list[str] = []
        for block in re.split(r"\n{2,}", markdown.strip()):
            normalized = re.sub(r"\s+", " ", block.strip()).lower()
            is_duplicate_candidate = len(normalized) >= 80
            if is_duplicate_candidate and normalized in seen:
                continue
            if is_duplicate_candidate:
                seen.add(normalized)
            deduped.append(block.strip())
        return "\n\n".join(deduped).strip()

    @staticmethod
    def _filter_wsj_navigation_blocks(markdown: str) -> str:
        """Drop WSJ promo/footer/navigation-heavy lines while keeping prose."""
        section_headers = {
            "News",
            "Markets",
            "Opinion",
            "WSJ Membership",
            "Customer Service",
            "Ads",
            "Tools & Features",
            "More",
            "Dow Jones Products",
            "Back to Top «",
            "English Edition",
            "Edition",
            "Use Alt + Down Arrow to expand.",
        }
        noisy_substrings = (
            "mod=wsjfooter",
            "mod=wsj_article_buy_widget",
            "customercenter.wsj.com",
            "wsjshop.com",
            "commercialpartnerships.wsj.com",
            "wsjmediakit.com",
            "classifieds.wsj.com",
            "wsjbg-adsmanager.com",
            "subscribe.wsj.com/default",
            "subscribe.wsj.com/membership",
            "corporate.wsj.com",
            "wsj.jobs",
            "djreprints.com",
            "dowjones.com/privacy-notice",
            "wsj.com/policy/legal-policies",
            "dowjones.com/terms-of-use",
            "facebook.com/wsj",
            "twitter.com/wsj",
            "instagram.com/wsj",
            "youtube.com/user/wsjdigitalnetwork",
            "snapchat.com/discover/wall-street-journal",
            "play.google.com/store/apps/details?id=wsj.reader_sp",
            "apps.apple.com/us/app/the-wall-street-journal",
            "back to top",
            "independent of the wall street journal newsroom.",
        )

        filtered_lines: list[str] = []
        for raw_line in markdown.splitlines():
            line = raw_line.strip()
            line_lower = line.lower()
            if not line:
                filtered_lines.append("")
                continue
            if line in section_headers:
                continue
            if any(token in line_lower for token in noisy_substrings):
                continue
            if line.startswith("*") and "https://www.wsj.com/" in line_lower:
                continue
            filtered_lines.append(raw_line)

        cleaned = "\n".join(filtered_lines)
        cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
        return cleaned.strip()

    @staticmethod
    def parse_published_at(value: str | None) -> datetime | None:
        """Parse published time into datetime."""
        if not value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None

    @staticmethod
    def extract_title(markdown: str, url: str) -> str:
        """Derive a title from markdown content or URL."""
        title_match = re.search(r"^#\s+(.+)", markdown, re.MULTILINE)
        candidate_title = None
        if title_match:
            candidate_title = title_match.group(1).strip()
        else:
            title_line_match = re.search(r"^Title:\s*(.+)", markdown, re.MULTILINE)
            if title_line_match:
                candidate_title = title_line_match.group(1).strip()
            else:
                for line in markdown.split("\n"):
                    stripped = line.strip()
                    if (
                        stripped
                        and not stripped.startswith("---")
                        and not stripped.startswith("#")
                    ):
                        candidate_title = stripped[:100]
                        break

        resolved = resolve_website_title(
            candidate_title,
            url=url,
            allow_network=False,
        )
        if resolved:
            return resolved

        parsed = urlparse(url)
        return parsed.netloc or url
