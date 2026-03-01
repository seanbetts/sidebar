#!/usr/bin/env python3
"""Migrate notes content to canonical Base64-encoded RTF plus plain-text metadata.

Usage:
    uv run backend/scripts/migrate_notes_to_rtf.py --dry-run
    uv run backend/scripts/migrate_notes_to_rtf.py --user-id <uuid>
    uv run backend/scripts/migrate_notes_to_rtf.py --require-zero-non-canonical
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import logging
import os
import sys
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

try:
    from .db_env import setup_environment
except ImportError:  # pragma: no cover - direct script invocation path
    from db_env import setup_environment  # type: ignore[no-redef]

logger = logging.getLogger(__name__)

MAX_NOTE_RTF_BYTES = 2_097_152
JSON_HEADROOM = 512
MAX_NOTE_CONTENT_B64_CHARS = ((MAX_NOTE_RTF_BYTES + 2) // 3) * 4 + JSON_HEADROOM
MIGRATION_VERSION_DEFAULT = "notes-rtf-v1"
NON_CANONICAL_SAMPLE_LIMIT = 20
NOTE_MODEL: Any = None


@dataclass
class MigrationFailure:
    note_id: str
    user_id: str
    reason: str


@dataclass
class MigrationReport:
    started_at: str
    completed_at: str | None = None
    migration_version: str = MIGRATION_VERSION_DEFAULT
    dry_run: bool = False
    total_rows: int = 0
    canonical_before: int = 0
    non_canonical_before: int = 0
    migrated: int = 0
    would_migrate: int = 0
    legacy_content_written: int = 0
    legacy_content_preserved: int = 0
    failures: list[MigrationFailure] = field(default_factory=list)
    non_canonical_after: int = 0
    non_canonical_after_sample_ids: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["failures"] = [asdict(failure) for failure in self.failures]
        return payload


@dataclass(frozen=True)
class MigrationOptions:
    dry_run: bool
    migration_version: str
    user_id: str | None = None
    include_deleted: bool = True
    limit: int | None = None
    require_zero_non_canonical: bool = False


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Migrate notes content to canonical Base64 RTF + plain text."
    )
    parser.add_argument("--user-id", help="Optional user id scope.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute migration result without writing changes.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Optional max number of rows to inspect.",
    )
    parser.add_argument(
        "--exclude-deleted",
        action="store_true",
        help="Skip soft-deleted rows (default is include all rows).",
    )
    parser.add_argument(
        "--migration-version",
        default=MIGRATION_VERSION_DEFAULT,
        help=f"Marker value for metadata.migrated_to_rtf_version (default: {MIGRATION_VERSION_DEFAULT}).",
    )
    parser.add_argument(
        "--require-zero-non-canonical",
        action="store_true",
        help="Exit non-zero when any non-canonical rows remain after migration.",
    )
    parser.add_argument(
        "--database-url",
        help="Override DATABASE_URL for this run.",
    )
    parser.add_argument(
        "--supabase",
        action="store_true",
        help="Force building DATABASE_URL from Supabase env vars.",
    )
    parser.add_argument(
        "--allow-production",
        action="store_true",
        help="Allow execution when APP_ENV is production.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON report to stdout.",
    )
    return parser.parse_args(argv)


def assert_safe_environment(*, allow_production: bool) -> None:
    app_env = os.getenv("APP_ENV", "").strip().lower()
    if app_env not in {"prod", "production"} or allow_production:
        return
    database_url = os.getenv("DATABASE_URL", "")
    parsed = urlparse(database_url) if database_url else None
    host = parsed.hostname if parsed else None
    db_name = parsed.path.lstrip("/") if parsed and parsed.path else None
    raise RuntimeError(
        "Refusing to run migration script in production environment "
        f"(APP_ENV={app_env!r}, host={host!r}, database={db_name!r}). "
        "Re-run with --allow-production only if this is intentional."
    )


def _rtf_escape_text(text: str) -> str:
    output: list[str] = []
    for char in text:
        if char == "\\":
            output.append("\\\\")
        elif char == "{":
            output.append("\\{")
        elif char == "}":
            output.append("\\}")
        elif char == "\t":
            output.append("\\tab ")
        else:
            codepoint = ord(char)
            if 0x20 <= codepoint <= 0x7E:
                output.append(char)
                continue
            signed = codepoint if codepoint <= 32767 else codepoint - 65536
            output.append(f"\\u{signed}?")
    return "".join(output)


def plain_text_to_rtf_bytes(plain_text: str) -> bytes:
    normalized = plain_text.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    escaped_lines = [_rtf_escape_text(line) for line in lines]
    body = "\\par\n".join(escaped_lines)
    prefix = (
        "{\\rtf1\\ansi\\deff0"
        "{\\fonttbl{\\f0\\fnil\\fcharset0 Helvetica;}}"
        "\\f0\\fs24 "
    )
    rtf = f"{prefix}{body}}}"
    return rtf.encode("utf-8")


def plain_text_to_rtf_base64(plain_text: str) -> str:
    rtf_bytes = plain_text_to_rtf_bytes(plain_text)
    return base64.b64encode(rtf_bytes).decode("ascii")


def canonical_content_issues(content: Any) -> list[str]:
    issues: list[str] = []
    if not isinstance(content, str):
        return ["content is not a string"]
    if len(content) > MAX_NOTE_CONTENT_B64_CHARS:
        issues.append("base64 content exceeds max encoded length")
        return issues
    try:
        decoded = base64.b64decode(content, validate=True)
    except (ValueError, binascii.Error):
        return ["content is not valid Base64"]
    if len(decoded) > MAX_NOTE_RTF_BYTES:
        issues.append("decoded RTF exceeds max byte size")
    if not decoded.startswith(b"{\\rtf"):
        issues.append("decoded content does not start with {\\rtf")
    return issues


def canonical_metadata_issues(metadata: Any) -> list[str]:
    if not isinstance(metadata, dict):
        return ["metadata is not a dict"]
    issues: list[str] = []
    if metadata.get("content_format") != "rtf":
        issues.append("metadata.content_format != rtf")
    plain_text = metadata.get("plain_text")
    if not isinstance(plain_text, str):
        issues.append("metadata.plain_text missing or not string")
    return issues


def is_note_canonical(note: Any) -> tuple[bool, list[str]]:
    issues = []
    issues.extend(canonical_content_issues(note.content))
    issues.extend(canonical_metadata_issues(note.metadata_))
    return len(issues) == 0, issues


def build_canonical_payload(
    legacy_content: str,
    metadata: dict[str, Any] | None,
    *,
    migrated_at: str,
    migration_version: str,
) -> tuple[str, dict[str, Any], bool]:
    canonical_content = plain_text_to_rtf_base64(legacy_content)
    next_metadata = dict(metadata or {})
    had_legacy_content = "legacy_content" in next_metadata
    if not had_legacy_content:
        next_metadata["legacy_content"] = legacy_content
    next_metadata["plain_text"] = legacy_content
    next_metadata["content_format"] = "rtf"
    next_metadata.setdefault("migrated_to_rtf_at", migrated_at)
    next_metadata.setdefault("migrated_to_rtf_version", migration_version)
    return canonical_content, next_metadata, had_legacy_content


def _build_note_query(db: Session, options: MigrationOptions):
    global NOTE_MODEL
    if NOTE_MODEL is None:
        from api.models.note import Note as NoteModel

        NOTE_MODEL = NoteModel
    query = db.query(NOTE_MODEL).order_by(NOTE_MODEL.created_at.asc(), NOTE_MODEL.id.asc())
    if options.user_id:
        query = query.filter(NOTE_MODEL.user_id == options.user_id)
    if not options.include_deleted:
        query = query.filter(NOTE_MODEL.deleted_at.is_(None))
    if options.limit is not None:
        query = query.limit(options.limit)
    return query


def _list_note_ids(db: Session, options: MigrationOptions) -> list[Any]:
    query = _build_note_query(db, options).with_entities(NOTE_MODEL.id)
    return [row[0] for row in query.all()]


def _scan_non_canonical_after(
    db: Session,
    options: MigrationOptions,
) -> tuple[int, list[str]]:
    non_canonical_count = 0
    sample_ids: list[str] = []
    for note_id in _list_note_ids(db, options):
        note = db.query(NOTE_MODEL).filter(NOTE_MODEL.id == note_id).first()
        if note is None:
            continue
        is_canonical, _ = is_note_canonical(note)
        if is_canonical:
            continue
        non_canonical_count += 1
        if len(sample_ids) < NON_CANONICAL_SAMPLE_LIMIT:
            sample_ids.append(str(note.id))
    return non_canonical_count, sample_ids


def migrate_notes(db: Session, options: MigrationOptions) -> MigrationReport:
    started = datetime.now(UTC).isoformat()
    report = MigrationReport(
        started_at=started,
        migration_version=options.migration_version,
        dry_run=options.dry_run,
    )
    migrated_at = datetime.now(UTC).isoformat()

    for note_id in _list_note_ids(db, options):
        note = db.query(NOTE_MODEL).filter(NOTE_MODEL.id == note_id).first()
        if note is None:
            continue
        report.total_rows += 1
        is_canonical, _issues = is_note_canonical(note)
        if is_canonical:
            report.canonical_before += 1
            continue

        legacy_content = note.content if isinstance(note.content, str) else ""
        try:
            canonical_content, next_metadata, had_legacy_content = build_canonical_payload(
                legacy_content,
                note.metadata_,
                migrated_at=migrated_at,
                migration_version=options.migration_version,
            )
            post_issues = []
            post_issues.extend(canonical_content_issues(canonical_content))
            post_issues.extend(canonical_metadata_issues(next_metadata))
            if post_issues:
                raise ValueError("; ".join(post_issues))

            if had_legacy_content:
                report.legacy_content_preserved += 1
            else:
                report.legacy_content_written += 1

            if options.dry_run:
                report.would_migrate += 1
                continue

            note.content = canonical_content
            note.metadata_ = next_metadata
            flag_modified(note, "metadata_")
            db.commit()
            report.migrated += 1
        except Exception as exc:  # pragma: no cover - error path validated via report
            db.rollback()
            report.failures.append(
                MigrationFailure(
                    note_id=str(note.id),
                    user_id=note.user_id,
                    reason=str(exc),
                )
            )

    report.non_canonical_before = report.total_rows - report.canonical_before

    if options.dry_run:
        report.non_canonical_after = report.non_canonical_before - report.would_migrate
    else:
        non_canonical_after, sample_ids = _scan_non_canonical_after(db, options)
        report.non_canonical_after = non_canonical_after
        report.non_canonical_after_sample_ids = sample_ids

    report.completed_at = datetime.now(UTC).isoformat()
    return report


def _should_fail(report: MigrationReport, options: MigrationOptions) -> bool:
    if report.failures:
        return True
    if options.require_zero_non_canonical and report.non_canonical_after > 0:
        return True
    return False


def _log_human_summary(report: MigrationReport) -> None:
    logger.info("Notes migration report")
    logger.info("  dry_run=%s", report.dry_run)
    logger.info("  total_rows=%s", report.total_rows)
    logger.info("  canonical_before=%s", report.canonical_before)
    logger.info("  non_canonical_before=%s", report.non_canonical_before)
    logger.info("  migrated=%s", report.migrated)
    logger.info("  would_migrate=%s", report.would_migrate)
    logger.info("  legacy_content_written=%s", report.legacy_content_written)
    logger.info("  legacy_content_preserved=%s", report.legacy_content_preserved)
    logger.info("  failures=%s", len(report.failures))
    logger.info("  non_canonical_after=%s", report.non_canonical_after)
    if report.non_canonical_after_sample_ids:
        logger.info(
            "  non_canonical_after_sample_ids=%s",
            ",".join(report.non_canonical_after_sample_ids),
        )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    setup_environment(database_url=args.database_url, supabase=args.supabase)
    global NOTE_MODEL
    from api.models.note import Note as NoteModel
    from api.db.session import SessionLocal, set_session_user_id
    NOTE_MODEL = NoteModel

    try:
        assert_safe_environment(allow_production=args.allow_production)
    except RuntimeError as exc:
        logger.error(str(exc))
        return 2

    options = MigrationOptions(
        dry_run=args.dry_run,
        migration_version=args.migration_version,
        user_id=args.user_id,
        include_deleted=not args.exclude_deleted,
        limit=args.limit,
        require_zero_non_canonical=args.require_zero_non_canonical,
    )

    with SessionLocal() as db:
        if options.user_id:
            set_session_user_id(db, options.user_id)
        report = migrate_notes(db, options)

    _log_human_summary(report)
    if args.json:
        json_payload = json.dumps(report.to_dict(), ensure_ascii=False, indent=2)
        sys.stdout.write(json_payload + "\n")

    if _should_fail(report, options):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
