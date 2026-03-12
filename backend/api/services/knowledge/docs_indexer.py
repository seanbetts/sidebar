"""Docs indexer: parse product docs into a structured in-memory catalog."""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


def _parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    """Extract YAML frontmatter and body from markdown text."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("---", 3)
    if end == -1:
        return {}, text
    raw = text[3:end].strip()
    body = text[end + 3 :].strip()

    metadata: dict[str, Any] = {}
    for line in raw.split("\n"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            items = [item.strip().strip("'\"") for item in value[1:-1].split(",")]
            metadata[key] = [item for item in items if item]
        else:
            metadata[key] = value
    return metadata, body


def _extract_headings(body: str) -> list[str]:
    """Extract markdown h2 headings from body text."""
    return re.findall(r"^##\s+(.+)$", body, re.MULTILINE)


def _extract_sections(body: str) -> list[dict[str, str]]:
    """Extract h2 sections as heading + content pairs."""
    parts = re.split(r"^(##\s+.+)$", body, flags=re.MULTILINE)
    sections: list[dict[str, str]] = []
    i = 1
    while i < len(parts) - 1:
        heading = parts[i].lstrip("#").strip()
        content = parts[i + 1].strip()
        sections.append({"heading": heading, "content": content})
        i += 2
    return sections


class DocsIndexer:
    """Parse docs/product/** into a structured catalog."""

    def __init__(self, docs_root: Path) -> None:
        """Initialize the indexer with a docs root directory."""
        self._docs_root = docs_root
        self._catalog: list[dict[str, Any]] = []

    @property
    def catalog(self) -> list[dict[str, Any]]:
        """Return the current indexed catalog."""
        return list(self._catalog)

    def build(self) -> None:
        """Scan docs root and rebuild the catalog."""
        catalog: list[dict[str, Any]] = []
        for md_path in sorted(self._docs_root.rglob("*.md")):
            try:
                text = md_path.read_text(encoding="utf-8")
            except OSError:
                logger.warning("Failed to read %s", md_path)
                continue
            metadata, body = _parse_frontmatter(text)
            if not metadata.get("title"):
                continue
            rel_path = str(md_path.relative_to(self._docs_root))
            skill_id_raw = metadata.get("skill_id")
            is_valid = isinstance(skill_id_raw, list | str) and skill_id_raw
            skill_id = skill_id_raw if is_valid else None
            catalog.append(
                {
                    "id": rel_path,
                    "title": metadata["title"],
                    "summary": metadata.get("summary", ""),
                    "tags": metadata.get("tags", []),
                    "audience": metadata.get("audience", ""),
                    "surfaces": metadata.get("surfaces", []),
                    "skill_id": skill_id,
                    "path": rel_path,
                    "headings": _extract_headings(body),
                    "sections": _extract_sections(body),
                }
            )
        self._catalog = catalog
        logger.info("DocsIndexer: indexed %d documents", len(catalog))
