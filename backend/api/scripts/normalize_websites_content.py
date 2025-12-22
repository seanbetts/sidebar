"""Normalize website titles and strip metadata labels from markdown content."""
import sys
import re
from pathlib import Path
from datetime import datetime, timezone

# Ensure backend is importable when running from repo root
sys.path.append(str(Path(__file__).resolve().parents[2]))

from api.db.session import SessionLocal  # noqa: E402
from api.models.website import Website  # noqa: E402

TITLE_RE = re.compile(r"^Title:\s*(.+)$", re.IGNORECASE | re.MULTILINE)
URL_RE = re.compile(r"^URL Source:\s*(.+)$", re.IGNORECASE | re.MULTILINE)
PUBLISHED_RE = re.compile(r"^Published Time:\s*(.+)$", re.IGNORECASE | re.MULTILINE)
CONTENT_RE = re.compile(r"^Markdown Content:\s*", re.IGNORECASE | re.MULTILINE)


def strip_metadata(content: str) -> str:
    content = TITLE_RE.sub("", content)
    content = URL_RE.sub("", content)
    content = PUBLISHED_RE.sub("", content)
    content = CONTENT_RE.sub("", content)
    # Collapse leading blank lines
    return content.lstrip()


def extract_title(content: str) -> str | None:
    match = TITLE_RE.search(content or "")
    if match:
        return match.group(1).strip()
    return None


def extract_published_time(content: str) -> datetime | None:
    match = PUBLISHED_RE.search(content or "")
    if not match:
        return None
    value = match.group(1).strip()
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def extract_url_source(content: str) -> str | None:
    match = URL_RE.search(content or "")
    if match:
        return match.group(1).strip()
    return None


def normalize():
    session = SessionLocal()
    updated = 0

    try:
        websites = session.query(Website).filter(Website.deleted_at.is_(None)).all()
        now = datetime.now(timezone.utc)
        for website in websites:
            content = website.content or ""
            title = extract_title(content)
            if title:
                website.title = title

            published = extract_published_time(content)
            if published:
                website.published_at = published

            source = extract_url_source(content)
            if source:
                website.source = source

            cleaned = strip_metadata(content)
            if cleaned != content:
                website.content = cleaned

            website.updated_at = now
            updated += 1

        session.commit()
    finally:
        session.close()

    print(f"Websites normalized: {updated}")


if __name__ == "__main__":
    normalize()
