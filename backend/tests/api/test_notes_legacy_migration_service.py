import json
import uuid
from datetime import UTC, datetime

from api.services.notes_document_types import note_document_from_plain_text
from api.services.notes_legacy_migration_service import NotesLegacyMigrationService
from sqlalchemy import text


def _insert_note(
    test_db,
    *,
    user_id: str,
    title: str,
    plain_text: str,
    document: dict[str, object] | None,
    deleted_at: datetime | None = None,
    is_folder_marker: bool = False,
) -> str:
    now = datetime.now(UTC)
    note_id = str(uuid.uuid4())
    test_db.execute(
        text(
            """
            INSERT INTO notes (
                id,
                user_id,
                title,
                document,
                document_version,
                plain_text,
                folder_path,
                pinned,
                pinned_order,
                is_folder_marker,
                is_archived,
                metadata,
                created_at,
                updated_at,
                last_opened_at,
                deleted_at
            ) VALUES (
                :id,
                :user_id,
                :title,
                CAST(:document AS jsonb),
                1,
                :plain_text,
                '',
                false,
                NULL,
                :is_folder_marker,
                false,
                CAST(:metadata AS jsonb),
                :created_at,
                :updated_at,
                NULL,
                :deleted_at
            )
            """
        ),
        {
            "id": note_id,
            "user_id": user_id,
            "title": title,
            "document": "null" if document is None else json.dumps(document),
            "plain_text": plain_text,
            "is_folder_marker": is_folder_marker,
            "metadata": "{}",
            "created_at": now,
            "updated_at": now,
            "deleted_at": deleted_at,
        },
    )
    return note_id


def test_list_notes_missing_semantic_documents_returns_only_active_note_rows(
    test_db,
):
    legacy_note_id = _insert_note(
        test_db,
        user_id="test_user",
        title="Legacy title",
        plain_text="Legacy title\nBody",
        document=None,
    )
    _insert_note(
        test_db,
        user_id="test_user",
        title="Migrated title",
        plain_text="Migrated title\nBody",
        document=note_document_from_plain_text("Migrated title\nBody"),
    )
    _insert_note(
        test_db,
        user_id="test_user",
        title="Deleted legacy",
        plain_text="Deleted legacy",
        document=None,
        deleted_at=datetime.now(UTC),
    )
    _insert_note(
        test_db,
        user_id="test_user",
        title="__folder__",
        plain_text="",
        document=None,
        is_folder_marker=True,
    )
    _insert_note(
        test_db,
        user_id="other_user",
        title="Other legacy",
        plain_text="Other legacy",
        document=None,
    )
    test_db.commit()

    rows = NotesLegacyMigrationService.list_note_ids_missing_documents(
        test_db,
        "test_user",
    )

    assert rows == [legacy_note_id]
