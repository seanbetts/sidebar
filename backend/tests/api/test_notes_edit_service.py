import importlib.util
import sys
import uuid
from datetime import timedelta
from pathlib import Path

import pytest
from sqlalchemy import text

from api.exceptions import BadRequestError, ConflictError
from api.services.notes_document_types import (
    NOTE_DOCUMENT_VERSION,
    note_document_from_plain_text,
)
from api.services.notes_service import NotesService


@pytest.fixture
def db_session(test_db):
    test_db.execute(text("ALTER TABLE notes DROP COLUMN IF EXISTS content"))
    test_db.execute(text("ALTER TABLE notes DROP COLUMN IF EXISTS content_format"))
    test_db.execute(text("ALTER TABLE notes ALTER COLUMN document SET NOT NULL"))
    test_db.commit()
    return test_db


def _document(plain_text: str) -> dict[str, object]:
    return note_document_from_plain_text(plain_text)


def _load_notes_edit_service_module():
    service_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "services"
        / "notes_edit_service.py"
    )
    assert service_path.exists(), "notes_edit_service.py must exist"

    spec = importlib.util.spec_from_file_location("notes_edit_service", service_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _refresh_note(db_session, note_id: uuid.UUID):
    return NotesService.get_note(db_session, "test_user", note_id, mark_opened=False)


def test_edit_note_renames_title_block_and_returns_updated_metadata(db_session):
    note = NotesService.create_note(db_session, "test_user", _document("Original title\nBody"))
    service_module = _load_notes_edit_service_module()

    result = service_module.NotesEditService.edit_note(
        db_session,
        "test_user",
        note.id,
        expected_updated_at=note.updated_at.isoformat(),
        operations=[
            {
                "type": "rename_note_title",
                "text": "Renamed title",
            }
        ],
    )

    refreshed = _refresh_note(db_session, note.id)
    assert refreshed is not None
    assert result == {
        "id": str(note.id),
        "title": "Renamed title",
        "updated_at": refreshed.updated_at.isoformat(),
    }
    assert refreshed.title == "Renamed title"
    assert refreshed.document_version == NOTE_DOCUMENT_VERSION
    assert refreshed.document["blocks"][0] == {
        "type": "title",
        "content": [{"text": "Renamed title", "marks": []}],
    }


def test_edit_note_replaces_one_body_block(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("Original title\nFirst body\nSecond body"),
    )
    service_module = _load_notes_edit_service_module()

    service_module.NotesEditService.edit_note(
        db_session,
        "test_user",
        note.id,
        expected_updated_at=note.updated_at.isoformat(),
        operations=[
            {
                "type": "replace_block",
                "index": 1,
                "block": {
                    "type": "paragraph",
                    "content": [{"text": "Replaced body", "marks": ["italic"]}],
                },
            }
        ],
    )

    refreshed = _refresh_note(db_session, note.id)
    assert refreshed is not None
    assert refreshed.plain_text == "Original title\nReplaced body\nSecond body"
    assert refreshed.document["blocks"][1] == {
        "type": "paragraph",
        "content": [{"text": "Replaced body", "marks": ["italic"]}],
    }


def test_edit_note_inserts_blocks_after_target_index(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("Original title\nFirst body"),
    )
    service_module = _load_notes_edit_service_module()

    service_module.NotesEditService.edit_note(
        db_session,
        "test_user",
        note.id,
        expected_updated_at=note.updated_at.isoformat(),
        operations=[
            {
                "type": "insert_blocks_after",
                "index": 1,
                "blocks": [
                    {
                        "type": "paragraph",
                        "content": [{"text": "Inserted one", "marks": []}],
                    },
                    {
                        "type": "paragraph",
                        "content": [{"text": "Inserted two", "marks": ["bold"]}],
                    },
                ],
            }
        ],
    )

    refreshed = _refresh_note(db_session, note.id)
    assert refreshed is not None
    assert refreshed.plain_text == "Original title\nFirst body\nInserted one\nInserted two"
    assert refreshed.document["blocks"][2]["content"][0]["text"] == "Inserted one"
    assert refreshed.document["blocks"][3]["content"][0]["text"] == "Inserted two"


def test_edit_note_deletes_one_body_block(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("Original title\nFirst body\nSecond body"),
    )
    service_module = _load_notes_edit_service_module()

    service_module.NotesEditService.edit_note(
        db_session,
        "test_user",
        note.id,
        expected_updated_at=note.updated_at.isoformat(),
        operations=[
            {
                "type": "delete_block",
                "index": 1,
            }
        ],
    )

    refreshed = _refresh_note(db_session, note.id)
    assert refreshed is not None
    assert refreshed.plain_text == "Original title\nSecond body"
    assert len(refreshed.document["blocks"]) == 2


def test_edit_note_applies_multiple_operations_in_sequence(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("Original title\nFirst body\nLast body"),
    )
    service_module = _load_notes_edit_service_module()

    service_module.NotesEditService.edit_note(
        db_session,
        "test_user",
        note.id,
        expected_updated_at=note.updated_at.isoformat(),
        operations=[
            {
                "type": "rename_note_title",
                "text": "Renamed title",
            },
            {
                "type": "replace_block",
                "index": 1,
                "block": {
                    "type": "paragraph",
                    "content": [{"text": "Replaced body", "marks": []}],
                },
            },
            {
                "type": "insert_blocks_after",
                "index": 1,
                "blocks": [
                    {
                        "type": "paragraph",
                        "content": [{"text": "Inserted body", "marks": []}],
                    }
                ],
            },
            {
                "type": "delete_block",
                "index": 3,
            },
        ],
    )

    refreshed = _refresh_note(db_session, note.id)
    assert refreshed is not None
    assert refreshed.plain_text == "Renamed title\nReplaced body\nInserted body"


def test_edit_note_rejects_stale_expected_updated_at(db_session):
    note = NotesService.create_note(db_session, "test_user", _document("Original title\nBody"))
    service_module = _load_notes_edit_service_module()
    stale_timestamp = (note.updated_at - timedelta(seconds=10)).isoformat()

    with pytest.raises(ConflictError):
        service_module.NotesEditService.edit_note(
            db_session,
            "test_user",
            note.id,
            expected_updated_at=stale_timestamp,
            operations=[
                {
                    "type": "rename_note_title",
                    "text": "Renamed title",
                }
            ],
        )


def test_edit_note_rejects_invalid_block_index(db_session):
    note = NotesService.create_note(db_session, "test_user", _document("Original title\nBody"))
    service_module = _load_notes_edit_service_module()

    with pytest.raises(BadRequestError, match="Invalid note edit operation"):
        service_module.NotesEditService.edit_note(
            db_session,
            "test_user",
            note.id,
            expected_updated_at=note.updated_at.isoformat(),
            operations=[
                {
                    "type": "replace_block",
                    "index": 9,
                    "block": {
                        "type": "paragraph",
                        "content": [{"text": "Out of bounds", "marks": []}],
                    },
                }
            ],
        )


def test_edit_note_rejects_replace_block_against_title_block(db_session):
    note = NotesService.create_note(db_session, "test_user", _document("Original title\nBody"))
    service_module = _load_notes_edit_service_module()

    with pytest.raises(BadRequestError, match="Invalid note edit operation"):
        service_module.NotesEditService.edit_note(
            db_session,
            "test_user",
            note.id,
            expected_updated_at=note.updated_at.isoformat(),
            operations=[
                {
                    "type": "replace_block",
                    "index": 0,
                    "block": {
                        "type": "paragraph",
                        "content": [{"text": "Illegal title replacement", "marks": []}],
                    },
                }
            ],
        )


def test_edit_note_rejects_title_blocks_in_insertions(db_session):
    note = NotesService.create_note(db_session, "test_user", _document("Original title\nBody"))
    service_module = _load_notes_edit_service_module()

    with pytest.raises(BadRequestError, match="Invalid note edit operation"):
        service_module.NotesEditService.edit_note(
            db_session,
            "test_user",
            note.id,
            expected_updated_at=note.updated_at.isoformat(),
            operations=[
                {
                    "type": "insert_blocks_after",
                    "index": 0,
                    "blocks": [
                        {
                            "type": "title",
                            "content": [{"text": "Illegal title block", "marks": []}],
                        }
                    ],
                }
            ],
        )


def test_edit_note_rejects_resulting_documents_that_fail_write_validation(db_session):
    note = NotesService.create_note(db_session, "test_user", _document("Original title\nBody"))
    service_module = _load_notes_edit_service_module()

    with pytest.raises(BadRequestError, match="Invalid note"):
        service_module.NotesEditService.edit_note(
            db_session,
            "test_user",
            note.id,
            expected_updated_at=note.updated_at.isoformat(),
            operations=[
                {
                    "type": "replace_block",
                    "index": 1,
                    "block": {
                        "type": "table",
                    },
                }
            ],
        )
