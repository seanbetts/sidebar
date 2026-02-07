"""Jina reader helper for website quick saves."""

from __future__ import annotations

import re
from datetime import datetime
from urllib.parse import urlparse

import httpx

from api.config import settings


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

        cleaned = markdown
        cleaned = re.sub(r"^Title:.*\n?", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"^URL Source:.*\n?", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"^Published Time:.*\n?", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"^Markdown Content:\s*", "", cleaned, flags=re.MULTILINE)
        cleaned = cleaned.lstrip()

        return metadata, cleaned

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
        if title_match:
            return title_match.group(1).strip()

        title_line_match = re.search(r"^Title:\s*(.+)", markdown, re.MULTILINE)
        if title_line_match:
            return title_line_match.group(1).strip()

        for line in markdown.split("\n"):
            stripped = line.strip()
            if (
                stripped
                and not stripped.startswith("---")
                and not stripped.startswith("#")
            ):
                return stripped[:100]

        parsed = urlparse(url)
        return parsed.netloc or url
