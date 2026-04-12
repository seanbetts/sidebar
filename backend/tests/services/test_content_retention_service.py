"""Tests for retention policy defaults and cleanup metrics."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from api import metrics
from api.models.website import Website
from api.services.content_retention_service import ContentRetentionService
from api.services.notes_document_types import note_document_from_plain_text
from api.services.notes_service import NotesService
from api.services.retention_policy import retention_policy_for
from api.services.websites_service import WebsitesService


def test_retention_policy_defaults_match_design_doc() -> None:
    notes = retention_policy_for("notes")
    websites = retention_policy_for("websites")
    keys = retention_policy_for("user_ai_provider_keys")

    assert notes.full_retention_days == 7
    assert notes.total_retention_days == 90
    assert notes.degrade_payload is True
    assert websites.total_retention_days == 60
    assert keys.total_retention_days == 7
    assert keys.degrade_payload is False


def test_cleanup_metrics_exist() -> None:
    assert metrics.data_cleanup_actions_total is not None
    assert metrics.data_cleanup_duration_seconds is not None
    assert metrics.data_cleanup_backlog_age_seconds is not None


def test_prune_notes_tombstones_rows_after_restore_window(test_db) -> None:
    now = datetime.now(UTC)
    note = NotesService.create_note(
        test_db,
        "user-1",
        note_document_from_plain_text("# Keep Title\n\nLarge body"),
    )
    note.deleted_at = now - timedelta(days=8)
    note.updated_at = note.deleted_at
    test_db.commit()

    summary = ContentRetentionService.prune_notes(test_db, now=now, limit=10)
    test_db.refresh(note)

    assert summary.tombstoned == 1
    assert note.payload_purged_at == now
    assert note.title == "# Keep Title"
    assert note.plain_text == ""
    assert note.document["blocks"][0]["type"] == "title"


def test_prune_websites_hard_deletes_rows_after_total_retention(test_db) -> None:
    now = datetime.now(UTC)
    website = WebsitesService.save_website(
        test_db,
        "user-1",
        url="https://example.com",
        title="Example",
        content="Large content body",
    )
    website.deleted_at = now - timedelta(days=61)
    website.updated_at = website.deleted_at
    test_db.commit()

    summary = ContentRetentionService.prune_websites(test_db, now=now, limit=10)

    assert summary.hard_deleted == 1
    assert test_db.query(Website).filter(Website.id == website.id).one_or_none() is None


def test_prune_websites_tombstones_rows_after_restore_window(test_db) -> None:
    now = datetime.now(UTC)
    website = WebsitesService.save_website(
        test_db,
        "user-1",
        url="https://example.com/tombstone",
        title="Example",
        content="Large content body",
    )
    website.deleted_at = now - timedelta(days=8)
    website.updated_at = website.deleted_at
    test_db.commit()

    summary = ContentRetentionService.prune_websites(test_db, now=now, limit=10)
    test_db.refresh(website)

    assert summary.tombstoned == 1
    assert website.payload_purged_at == now
    assert website.title == "Example"
    assert website.content == ""
