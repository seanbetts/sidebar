"""One-off migration script to move notes from filesystem into Postgres."""
import os
import re
import sys
from pathlib import Path
from datetime import datetime, timezone

# Ensure backend is importable when running from repo root
sys.path.append(str(Path(__file__).resolve().parents[2]))

from api.db.session import SessionLocal  # noqa: E402
from api.models.note import Note  # noqa: E402

WORKSPACE_BASE = os.getenv("WORKSPACE_BASE", "/workspace")
NOTES_ROOT = Path(WORKSPACE_BASE) / "notes"
H1_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)


def extract_title(content: str, fallback: str) -> str:
    match = H1_PATTERN.search(content or "")
    if match:
        return match.group(1).strip()
    return fallback


def normalize_folder(path: Path) -> str:
    if str(path) == ".":
        return ""
    return path.as_posix()


def file_timestamps(path: Path) -> tuple[datetime, datetime]:
    stat = path.stat()
    created_ts = getattr(stat, "st_birthtime", None)
    created_at = datetime.fromtimestamp(created_ts or stat.st_mtime, tz=timezone.utc)
    updated_at = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
    return created_at, updated_at


def migrate():
    if not NOTES_ROOT.exists():
        raise SystemExit(f"Notes folder not found: {NOTES_ROOT}")

    session = SessionLocal()
    created = 0
    skipped = 0

    try:
        for file_path in NOTES_ROOT.rglob("*.md"):
            if not file_path.is_file():
                continue

            rel_path = file_path.relative_to(NOTES_ROOT)
            title = file_path.stem
            content = file_path.read_text(encoding="utf-8")
            title = extract_title(content, title)
            folder = normalize_folder(rel_path.parent)
            created_at, updated_at = file_timestamps(file_path)

            exists = session.query(Note).filter(
                Note.title == title,
                Note.metadata_["folder"].astext == folder,
                Note.deleted_at.is_(None)
            ).first()
            if exists:
                skipped += 1
                continue

            note = Note(
                title=title,
                content=content,
                metadata_={"folder": folder, "pinned": False},
                created_at=created_at,
                updated_at=updated_at,
                last_opened_at=None,
                deleted_at=None
            )
            session.add(note)
            created += 1

        session.commit()
    finally:
        session.close()

    print(f"Migration complete. Created: {created}, Skipped (duplicate title): {skipped}")


if __name__ == "__main__":
    migrate()
