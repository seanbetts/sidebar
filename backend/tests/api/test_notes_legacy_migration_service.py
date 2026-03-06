import uuid
from datetime import UTC, datetime

from api.models.note import Note
from api.services.notes_document_types import note_document_from_plain_text
from api.services.notes_legacy_migration_service import NotesLegacyMigrationService
from api.services.notes_write_contract import plain_text_to_rtf_base64


def _legacy_note(
    *,
    user_id: str,
    title: str,
    plain_text: str,
    document: dict[str, object] | None,
    deleted_at: datetime | None = None,
    is_folder_marker: bool = False,
) -> Note:
    now = datetime.now(UTC)
    return Note(
        id=uuid.uuid4(),
        user_id=user_id,
        title=title,
        content=plain_text_to_rtf_base64(plain_text),
        document=document,
        document_version=1,
        plain_text=plain_text,
        content_format="rtf",
        folder_path="",
        pinned=False,
        pinned_order=None,
        is_folder_marker=is_folder_marker,
        is_archived=False,
        metadata_={},
        created_at=now,
        updated_at=now,
        deleted_at=deleted_at,
    )


def test_list_notes_missing_semantic_documents_returns_only_active_note_rows(
    test_db,
):
    legacy_note = _legacy_note(
        user_id="test_user",
        title="Legacy title",
        plain_text="Legacy title\nBody",
        document=None,
    )
    migrated_note = _legacy_note(
        user_id="test_user",
        title="Migrated title",
        plain_text="Migrated title\nBody",
        document=note_document_from_plain_text("Migrated title\nBody"),
    )
    deleted_legacy = _legacy_note(
        user_id="test_user",
        title="Deleted legacy",
        plain_text="Deleted legacy",
        document=None,
        deleted_at=datetime.now(UTC),
    )
    folder_marker = _legacy_note(
        user_id="test_user",
        title="__folder__",
        plain_text="",
        document=None,
        is_folder_marker=True,
    )
    other_user_legacy = _legacy_note(
        user_id="other_user",
        title="Other legacy",
        plain_text="Other legacy",
        document=None,
    )

    test_db.add_all(
        [
            legacy_note,
            migrated_note,
            deleted_legacy,
            folder_marker,
            other_user_legacy,
        ]
    )
    test_db.commit()

    rows = NotesLegacyMigrationService.list_note_ids_missing_documents(
        test_db,
        "test_user",
    )

    assert rows == [str(legacy_note.id)]
