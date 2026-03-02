from datetime import timedelta

from api.services.file_ingestion_service import FileIngestionService
from api.services.files_sync_service import FilesSyncService
from api.services.notes_content_codec import canonical_note_content_from_plain_text
from api.services.notes_service import NotesService
from api.services.notes_sync_service import NotesSyncService
from api.services.websites_service import WebsitesService
from api.services.websites_sync_service import WebsitesSyncService


def _canonical_pair(plain_text: str) -> tuple[str, str]:
    canonical = canonical_note_content_from_plain_text(plain_text)
    return canonical.content, canonical.plain_text


def test_notes_sync_conflict(test_db):
    original_content, original_plain_text = _canonical_pair("# Title\n\nBody")
    note = NotesService.create_note(
        test_db,
        "user-1",
        original_content,
        plain_text=original_plain_text,
    )
    updated_content, updated_plain_text = _canonical_pair("Updated")
    stale = note.updated_at - timedelta(seconds=10)
    result = NotesSyncService.sync_operations(
        test_db,
        "user-1",
        {
            "last_sync": None,
            "operations": [
                {
                    "operation_id": "op-1",
                    "op": "update",
                    "id": str(note.id),
                    "content": updated_content,
                    "plain_text": updated_plain_text,
                    "client_updated_at": stale.isoformat(),
                }
            ],
        },
    )
    assert result.conflicts


def test_notes_sync_move_unpins_note(test_db):
    content, plain_text = _canonical_pair("# Title\n\nBody")
    note = NotesService.create_note(
        test_db,
        "user-1",
        content,
        plain_text=plain_text,
    )
    NotesService.update_pinned(test_db, "user-1", note.id, True)

    result = NotesSyncService.sync_operations(
        test_db,
        "user-1",
        {
            "last_sync": None,
            "operations": [
                {
                    "operation_id": "op-move",
                    "op": "move",
                    "id": str(note.id),
                    "folder": "Inbox",
                }
            ],
        },
    )

    assert not result.conflicts
    moved = NotesService.get_note(test_db, "user-1", note.id, mark_opened=False)
    assert moved is not None
    assert moved.folder_path == "Inbox"
    assert moved.pinned is False
    assert moved.pinned_order is None


def test_notes_sync_archive_unpins_note(test_db):
    content, plain_text = _canonical_pair("# Title\n\nBody")
    note = NotesService.create_note(
        test_db,
        "user-1",
        content,
        plain_text=plain_text,
    )
    NotesService.update_pinned(test_db, "user-1", note.id, True)

    result = NotesSyncService.sync_operations(
        test_db,
        "user-1",
        {
            "last_sync": None,
            "operations": [
                {
                    "operation_id": "op-archive",
                    "op": "archive",
                    "id": str(note.id),
                    "archived": True,
                }
            ],
        },
    )

    assert not result.conflicts
    archived = NotesService.get_note(test_db, "user-1", note.id, mark_opened=False)
    assert archived is not None
    assert archived.folder_path == "Archive"
    assert archived.pinned is False
    assert archived.pinned_order is None


def test_notes_sync_delete_unpins_note(test_db):
    content, plain_text = _canonical_pair("# Title\n\nBody")
    note = NotesService.create_note(
        test_db,
        "user-1",
        content,
        plain_text=plain_text,
    )
    NotesService.update_pinned(test_db, "user-1", note.id, True)

    result = NotesSyncService.sync_operations(
        test_db,
        "user-1",
        {
            "last_sync": None,
            "operations": [
                {
                    "operation_id": "op-delete",
                    "op": "delete",
                    "id": str(note.id),
                }
            ],
        },
    )

    assert not result.conflicts
    deleted = NotesService.get_note(
        test_db,
        "user-1",
        note.id,
        mark_opened=False,
        include_deleted=True,
    )
    assert deleted is not None
    assert deleted.deleted_at is not None
    assert deleted.pinned is False
    assert deleted.pinned_order is None


def test_websites_sync_conflict(test_db):
    website = WebsitesService.save_website(
        test_db,
        "user-1",
        url="https://example.com/sync",
        title="Sync",
        content="Content",
        source="https://example.com/sync",
    )
    stale = website.updated_at - timedelta(seconds=10)
    result = WebsitesSyncService.sync_operations(
        test_db,
        "user-1",
        {
            "operations": [
                {
                    "operation_id": "op-2",
                    "op": "rename",
                    "id": str(website.id),
                    "title": "New Title",
                    "client_updated_at": stale.isoformat(),
                }
            ]
        },
    )
    assert result.conflicts


def test_files_sync_conflict(test_db):
    file_record = FileIngestionService.create_ingestion(
        test_db,
        "user-1",
        filename_original="sync.txt",
        path="sync.txt",
        mime_original="text/plain",
        size_bytes=10,
    )[0]
    stale = file_record.updated_at - timedelta(seconds=10)
    result = FilesSyncService.sync_operations(
        test_db,
        "user-1",
        {
            "operations": [
                {
                    "operation_id": "op-3",
                    "op": "rename",
                    "id": str(file_record.id),
                    "filename": "sync-renamed.txt",
                    "client_updated_at": stale.isoformat(),
                }
            ]
        },
    )
    assert result.conflicts
