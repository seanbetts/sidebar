"""Jina reader helper for website quick saves."""

from __future__ import annotations

import re
from datetime import datetime
from urllib.parse import urlparse

import httpx

from api.config import settings
from api.services.website_title_service import resolve_website_title


class JinaService:
    """Fetch and parse markdown content from Jina Reader API."""

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
            response = client.get(jina_url, headers=headers)
            response.raise_for_status()
            return response.text

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

        end_markers = (
            "Continue reading your article with",
            "Advertisement",
            "This copy is for your personal, non-commercial use only.",
        )
        for marker in end_markers:
            idx = cleaned.find(marker)
            if idx >= 0:
                cleaned = cleaned[:idx]
                break

        cleaned = re.sub(
            r"(?m)^!\[[^\]]*]\(https?://(?:analytics\.twitter\.com|t\.co/1/i/adsct|bat\.bing\.com|sync\.intentiq\.com)[^)]+\)\s*",
            "",
            cleaned,
        )
        cleaned = re.sub(r"(?m)^\d+\.\s+WSJ\..*\n?", "", cleaned)
        cleaned = re.sub(
            r"(?m)^(Share|Resize|Listen|\(\d+\s+min\))\s*$\n?",
            "",
            cleaned,
        )
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
