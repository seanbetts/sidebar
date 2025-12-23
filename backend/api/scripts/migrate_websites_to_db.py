"""One-off migration script to move website markdown files into Postgres."""
import os
import re
import sys
from pathlib import Path
from datetime import datetime, timezone, date
from urllib.parse import urlparse, urlunparse
import yaml

# Ensure backend is importable when running from repo root
sys.path.append(str(Path(__file__).resolve().parents[2]))

from api.db.session import SessionLocal  # noqa: E402
from api.models.website import Website  # noqa: E402

WORKSPACE_BASE = os.getenv("WORKSPACE_BASE", "/workspace")
WEBSITES_ROOT = Path(WORKSPACE_BASE) / "documents" / "Websites"
H1_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)
PUBLISHED_PATTERN = re.compile(r"^Published(?:\s+time)?:\s*(.+)$", re.IGNORECASE | re.MULTILINE)


def parse_frontmatter(content: str) -> tuple[dict, str]:
    if not content.startswith("---"):
        return {}, content
    parts = content.split("---", 2)
    if len(parts) < 3:
        return {}, content
    _, frontmatter, body = parts
    try:
        data = yaml.safe_load(frontmatter) or {}
    except yaml.YAMLError:
        data = {}
    return data, body.lstrip("\n")


def extract_title(content: str, fallback: str) -> str:
    match = H1_PATTERN.search(content or "")
    if match:
        return match.group(1).strip()
    return fallback


def parse_datetime(value) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, date):
        return datetime(value.year, value.month, value.day, tzinfo=timezone.utc)
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def normalize_url(url: str) -> tuple[str, str, str]:
    parsed = urlparse(url)
    stripped = parsed._replace(query="", fragment="")
    normalized = urlunparse(stripped)
    domain = parsed.hostname or ""
    return normalized, url, domain


def extract_published_at(content: str) -> datetime | None:
    match = PUBLISHED_PATTERN.search(content or "")
    if not match:
        return None
    return parse_datetime(match.group(1).strip())


def migrate():
    if not WEBSITES_ROOT.exists():
        raise SystemExit(f"Websites folder not found: {WEBSITES_ROOT}")

    session = SessionLocal()
    created = 0
    skipped = 0

    try:
        for file_path in WEBSITES_ROOT.rglob("*.md"):
            if not file_path.is_file():
                continue

            raw_content = file_path.read_text(encoding="utf-8")
            frontmatter, body = parse_frontmatter(raw_content)

            source = frontmatter.get("source")
            saved_at = parse_datetime(frontmatter.get("date"))

            title = extract_title(body, file_path.stem)
            published_at = extract_published_at(body)

            if not source:
                skipped += 1
                continue

            url, url_full, domain = normalize_url(source)
            if not url or not domain:
                skipped += 1
                continue

            exists = session.query(Website).filter(Website.url == url, Website.deleted_at.is_(None)).first()
            if exists:
                skipped += 1
                continue

            now = datetime.now(timezone.utc)
            website = Website(
                url=url,
                url_full=url_full,
                domain=domain,
                title=title,
                content=body,
                source=source,
                saved_at=saved_at,
                published_at=published_at,
            metadata_={"pinned": False, "archived": False},
                created_at=now,
                updated_at=now,
                last_opened_at=None,
                deleted_at=None
            )
            session.add(website)
            created += 1

        session.commit()
    finally:
        session.close()

    print(f"Migration complete. Created: {created}, Skipped: {skipped}")


if __name__ == "__main__":
    migrate()
