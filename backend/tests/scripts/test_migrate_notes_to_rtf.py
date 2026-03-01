"""Tests for backend/scripts/migrate_notes_to_rtf.py."""

from __future__ import annotations

import base64
import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy.orm.attributes import flag_modified

from api.models.note import Note
from scripts.migrate_notes_to_rtf import (
    MigrationOptions,
    build_canonical_payload,
    canonical_content_issues,
    is_note_canonical,
    migrate_notes,
    plain_text_to_rtf_base64,
)


@pytest.fixture
def db_session(test_db):
    return test_db


def _create_legacy_note(db_session, *, user_id: str, title: str, content: str) -> Note:
    now = datetime.now(UTC)
    note = Note(
        id=uuid.uuid4(),
        user_id=user_id,
        title=title,
        content=content,
        metadata_={"folder": "", "pinned": False},
        created_at=now,
        updated_at=now,
        last_opened_at=None,
        deleted_at=None,
    )
    db_session.add(note)
    db_session.commit()
    return note


def test_plain_text_to_rtf_base64_produces_valid_canonical_payload() -> None:
    payload = plain_text_to_rtf_base64("Hello\n{world}\\tab")
    decoded = base64.b64decode(payload, validate=True)

    assert decoded.startswith(b"{\\rtf")
    assert canonical_content_issues(payload) == []


def test_build_canonical_payload_preserves_existing_legacy_content() -> None:
    content, metadata, had_legacy = build_canonical_payload(
        "new content",
        {"legacy_content": "old content", "folder": "Work"},
        migrated_at=datetime.now(UTC).isoformat(),
        migration_version="notes-rtf-v1",
    )

    assert had_legacy is True
    assert canonical_content_issues(content) == []
    assert metadata["legacy_content"] == "old content"
    assert metadata["plain_text"] == "new content"
    assert metadata["content_format"] == "rtf"


def test_migrate_notes_converts_legacy_rows_and_is_idempotent(db_session) -> None:
    legacy_text = "# Legacy Note\n\nBody"
    note = _create_legacy_note(
        db_session,
        user_id="test_user",
        title="Legacy Note",
        content=legacy_text,
    )

    first = migrate_notes(
        db_session,
        MigrationOptions(
            dry_run=False,
            migration_version="notes-rtf-v1",
            user_id="test_user",
        ),
    )
    db_session.refresh(note)
    canonical_after_first, _ = is_note_canonical(note)

    second = migrate_notes(
        db_session,
        MigrationOptions(
            dry_run=False,
            migration_version="notes-rtf-v1",
            user_id="test_user",
        ),
    )
    db_session.refresh(note)

    assert first.migrated == 1
    assert canonical_after_first is True
    assert (note.metadata_ or {}).get("plain_text") == legacy_text
    assert (note.metadata_ or {}).get("legacy_content") == legacy_text
    assert second.migrated == 0
    assert second.canonical_before == 1


def test_migrate_notes_dry_run_does_not_mutate_rows(db_session) -> None:
    legacy_text = "plain legacy note"
    note = _create_legacy_note(
        db_session,
        user_id="test_user",
        title="Legacy Dry Run",
        content=legacy_text,
    )

    report = migrate_notes(
        db_session,
        MigrationOptions(
            dry_run=True,
            migration_version="notes-rtf-v1",
            user_id="test_user",
        ),
    )
    db_session.refresh(note)

    assert report.would_migrate == 1
    assert note.content == legacy_text
    assert (note.metadata_ or {}).get("plain_text") is None


def test_migrate_notes_preserves_write_once_legacy_content(db_session) -> None:
    note = _create_legacy_note(
        db_session,
        user_id="test_user",
        title="Legacy Marker Preservation",
        content="new content",
    )
    metadata = dict(note.metadata_ or {})
    metadata["legacy_content"] = "original snapshot"
    note.metadata_ = metadata
    flag_modified(note, "metadata_")
    db_session.commit()

    report = migrate_notes(
        db_session,
        MigrationOptions(
            dry_run=False,
            migration_version="notes-rtf-v1",
            user_id="test_user",
        ),
    )
    db_session.refresh(note)

    assert report.migrated == 1
    assert report.legacy_content_preserved == 1
    assert (note.metadata_ or {}).get("legacy_content") == "original snapshot"
    assert (note.metadata_ or {}).get("plain_text") == "new content"
