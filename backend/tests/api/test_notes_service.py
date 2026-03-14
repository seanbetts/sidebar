import importlib.util
import sys
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import text
from api.exceptions import BadRequestError, ConflictError
from api.services.notes_document_types import note_document_from_plain_text
from api.schemas.filters import NoteFilters
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


def _load_notes_script_module(script_name: str, module_name: str):
    script_path = (
        Path(__file__).resolve().parents[2]
        / "skills"
        / "notes"
        / "scripts"
        / script_name
    )
    spec = importlib.util.spec_from_file_location(module_name, script_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _load_save_note_document_module():
    return _load_notes_script_module(
        "save_note_document.py",
        "save_note_document_script",
    )


def _load_scratchpad_get_module():
    return _load_notes_script_module("scratchpad_get.py", "scratchpad_get_script")


def _load_scratchpad_update_module():
    return _load_notes_script_module(
        "scratchpad_update.py",
        "scratchpad_update_script",
    )


def _load_scratchpad_clear_module():
    return _load_notes_script_module("scratchpad_clear.py", "scratchpad_clear_script")


def _load_read_note_module():
    return _load_notes_script_module("read_note.py", "read_note_script")


def _load_download_note_module():
    return _load_notes_script_module("download_note.py", "download_note_script")


def test_create_and_read_note(db_session):
    content = "# Test Note\n\nBody"
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document(content),
        folder="Work",
    )

    assert note.title == "# Test Note"
    fetched = NotesService.get_note(db_session, "test_user", note.id, mark_opened=True)
    assert fetched is not None
    assert fetched.title == "# Test Note"
    assert fetched.document == _document(content)
    assert fetched.document_version == 1
    assert fetched.plain_text == content
    assert fetched.last_opened_at is not None


def test_update_note_title(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Old Title\n\nBody"),
    )
    updated = NotesService.update_note(
        db_session,
        "test_user",
        note.id,
        _document("# New Title\n\nBody"),
    )

    assert updated.title == "# New Title"
    assert updated.document == _document("# New Title\n\nBody")
    assert updated.document_version == 1
    assert updated.plain_text == "# New Title\n\nBody"


def test_create_note_uses_block_zero_plain_text_line_for_title(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("\n\n  ## Derived Title  \nBody"),
    )

    assert note.title == "New Note"
    assert note.plain_text == "\n\n  ## Derived Title  \nBody"


def test_create_note_falls_back_to_new_note_for_blank_plain_text(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("\n \n\t"),
    )

    assert note.title == "New Note"
    assert note.plain_text == "\n \n\t"


def test_create_note_derives_title_and_plain_text_from_semantic_document_projection(
    db_session,
):
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "# Semantic Title", "marks": ["bold"]}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body line", "marks": ["italic"]}],
            },
        ],
    }

    note = NotesService.create_note(db_session, "test_user", document)

    assert note.title == "# Semantic Title"
    assert note.plain_text == "# Semantic Title\nBody line"
    assert note.document == document


def test_create_note_preserves_literal_hash_prefix_from_semantic_document(db_session):
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "## Literal heading markers", "marks": []}],
            }
        ],
    }

    note = NotesService.create_note(db_session, "test_user", document)

    assert note.title == "## Literal heading markers"
    assert note.plain_text == "## Literal heading markers"
    assert note.document == document


def test_update_note_derives_title_and_plain_text_from_semantic_document_projection(
    db_session,
):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Before\nOld body"),
    )
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "# After Title", "marks": ["underline"]}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Updated body", "marks": []}],
            },
        ],
    }

    updated = NotesService.update_note(db_session, "test_user", note.id, document)

    assert updated.title == "# After Title"
    assert updated.plain_text == "# After Title\nUpdated body"
    assert updated.document == document


def test_save_note_document_script_create_accepts_semantic_document_without_heading_injection(
    db_session, monkeypatch
):
    module = _load_save_note_document_module()
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Semantic Title", "marks": ["bold"]}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body line", "marks": ["italic"]}],
            },
        ],
    }

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    result = module.save_note_document_database(
        user_id="test_user",
        document=document,
        mode="create",
        folder="Work",
    )

    created = NotesService.get_note(
        db_session,
        "test_user",
        uuid.UUID(result["id"]),
        mark_opened=False,
    )
    assert created is not None
    assert result["title"] == "Semantic Title"
    assert created.title == "Semantic Title"
    assert created.plain_text == "Semantic Title\nBody line"
    assert created.document == document


def test_save_note_document_script_update_accepts_semantic_document(db_session, monkeypatch):
    original = NotesService.create_note(
        db_session,
        "test_user",
        _document("Original title\nOriginal body"),
    )
    module = _load_save_note_document_module()
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Updated title", "marks": ["underline"]}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Updated body", "marks": []}],
            },
        ],
    }

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    result = module.save_note_document_database(
        user_id="test_user",
        document=document,
        mode="update",
        note_id=str(original.id),
    )

    updated = NotesService.get_note(db_session, "test_user", original.id, mark_opened=False)
    assert updated is not None
    assert result["id"] == str(original.id)
    assert result["title"] == "Updated title"
    assert updated.title == "Updated title"
    assert updated.plain_text == "Updated title\nUpdated body"
    assert updated.document == document


def test_save_note_document_script_append_concatenates_document_blocks_in_order(
    db_session, monkeypatch
):
    original = NotesService.create_note(
        db_session,
        "test_user",
        {
            "version": 1,
            "blocks": [
                {
                    "type": "title",
                    "content": [{"text": "Original title", "marks": ["bold"]}],
                }
            ],
        },
    )
    module = _load_save_note_document_module()
    appended_document = {
        "version": 1,
        "blocks": [
            {
                "type": "paragraph",
                "content": [{"text": "Appended line", "marks": ["italic"]}],
            }
        ],
    }

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    result = module.save_note_document_database(
        user_id="test_user",
        document=appended_document,
        mode="append",
        note_id=str(original.id),
    )

    updated = NotesService.get_note(db_session, "test_user", original.id, mark_opened=False)
    assert updated is not None
    assert result["id"] == str(original.id)
    assert updated.title == "Original title"
    assert updated.plain_text == "Original title\nAppended line"
    assert updated.document == {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Original title", "marks": ["bold"]}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Appended line", "marks": ["italic"]}],
            },
        ],
    }


def test_save_note_document_script_append_rejects_documents_outside_phase_one_projection(
    db_session, monkeypatch
):
    original = NotesService.create_note(
        db_session,
        "test_user",
        _document("Original title"),
    )
    module = _load_save_note_document_module()
    appended_document = {
        "version": 1,
        "blocks": [
            {
                "type": "table",
                "rows": [],
            }
        ],
    }

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    with pytest.raises(
        BadRequestError,
        match="unsupported block type",
    ):
        module.save_note_document_database(
            user_id="test_user",
            document=appended_document,
            mode="append",
            note_id=str(original.id),
        )


def test_scratchpad_get_returns_document_and_plain_text_without_markdown_heading(
    db_session, monkeypatch
):
    module = _load_scratchpad_get_module()

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    result = module.get_scratchpad("test_user")
    note = NotesService.get_note(
        db_session,
        "test_user",
        uuid.UUID(result["id"]),
        mark_opened=False,
    )

    assert note is not None
    assert result["title"] == module.SCRATCHPAD_TITLE
    assert result["plain_text"] == module.SCRATCHPAD_TITLE
    assert result["plain_text"].startswith(module.SCRATCHPAD_TITLE)
    assert not result["plain_text"].startswith(f"# {module.SCRATCHPAD_TITLE}")
    assert result["document"] == note.document
    assert note.plain_text == module.SCRATCHPAD_TITLE


def test_scratchpad_update_stores_body_as_semantic_document_without_markdown_heading(
    db_session, monkeypatch
):
    module = _load_scratchpad_update_module()
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "paragraph",
                "content": [{"text": "Body line", "marks": ["italic"]}],
            }
        ],
    }

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    result = module.update_scratchpad("test_user", document)
    note = NotesService.get_note(
        db_session,
        "test_user",
        uuid.UUID(result["id"]),
        mark_opened=False,
    )

    assert note is not None
    assert result["title"] == module.SCRATCHPAD_TITLE
    assert note.title == module.SCRATCHPAD_TITLE
    assert note.plain_text == f"{module.SCRATCHPAD_TITLE}\nBody line"
    assert not note.plain_text.startswith(f"# {module.SCRATCHPAD_TITLE}")
    assert note.document == {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": module.SCRATCHPAD_TITLE, "marks": []}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body line", "marks": ["italic"]}],
            },
        ],
    }


def test_scratchpad_clear_resets_to_plain_title_document_without_markdown_heading(
    db_session, monkeypatch
):
    update_module = _load_scratchpad_update_module()
    clear_module = _load_scratchpad_clear_module()

    monkeypatch.setattr(update_module, "SessionLocal", lambda: db_session)
    monkeypatch.setattr(clear_module, "SessionLocal", lambda: db_session)

    seeded = update_module.update_scratchpad(
        "test_user",
        {
            "version": 1,
            "blocks": [
                {
                    "type": "paragraph",
                    "content": [{"text": "Scratch body", "marks": ["bold"]}],
                }
            ],
        },
    )

    result = clear_module.clear_scratchpad("test_user")
    note = NotesService.get_note(
        db_session,
        "test_user",
        uuid.UUID(seeded["id"]),
        mark_opened=False,
    )

    assert note is not None
    assert result["id"] == seeded["id"]
    assert note.title == clear_module.SCRATCHPAD_TITLE
    assert note.plain_text == clear_module.SCRATCHPAD_TITLE
    assert not note.plain_text.startswith(f"# {clear_module.SCRATCHPAD_TITLE}")
    assert note.document == {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": clear_module.SCRATCHPAD_TITLE, "marks": []}],
            }
        ],
    }


def test_read_note_script_returns_canonical_document_and_plain_text(db_session, monkeypatch):
    note = NotesService.create_note(
        db_session,
        "test_user",
        {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Semantic title", "marks": ["bold"]}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body line", "marks": ["italic"]}],
                },
            ],
        },
    )
    module = _load_read_note_module()

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    result = module.read_note_database("test_user", str(note.id))

    assert result["id"] == str(note.id)
    assert result["title"] == "Semantic title"
    assert result["document"] == note.document
    assert result["plain_text"] == "Semantic title\nBody line"


def test_download_note_script_treats_plain_text_as_export_only(db_session, monkeypatch):
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Export title", "marks": ["underline"]}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Export body", "marks": []}],
            },
        ],
    }
    note = NotesService.create_note(db_session, "test_user", document)
    module = _load_download_note_module()

    monkeypatch.setattr(module, "SessionLocal", lambda: db_session)

    result = module.download_note_database("test_user", str(note.id))
    refreshed = NotesService.get_note(db_session, "test_user", note.id, mark_opened=False)

    assert result == {
        "content": "Export title\nExport body",
        "filename": "Export title.txt",
    }
    assert refreshed is not None
    assert refreshed.document == document
    assert refreshed.plain_text == "Export title\nExport body"


def test_update_folder_and_pinned(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Folder Note\n\nBody"),
    )
    moved = NotesService.update_folder(
        db_session, "test_user", note.id, "Projects/Alpha"
    )
    pinned = NotesService.update_pinned(db_session, "test_user", note.id, True)

    assert moved.folder_path == "Projects/Alpha"
    assert pinned.pinned is True


def test_update_pinned_assigns_next_order(db_session):
    note_a = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Alpha\n\nBody"),
    )
    note_b = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Beta\n\nBody"),
    )

    pinned_a = NotesService.update_pinned(db_session, "test_user", note_a.id, True)
    pinned_b = NotesService.update_pinned(db_session, "test_user", note_b.id, True)

    assert pinned_a.pinned_order == 0
    assert pinned_b.pinned_order == 1


def test_update_folder_can_clear_pinned_state(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Move Me\n\nBody"),
    )
    NotesService.update_pinned(db_session, "test_user", note.id, True)

    moved = NotesService.update_folder(
        db_session,
        "test_user",
        note.id,
        "Projects/Beta",
        clear_pinned=True,
    )

    assert moved.folder_path == "Projects/Beta"
    assert moved.pinned is False
    assert moved.pinned_order is None


def test_list_notes_filters(db_session):
    now = datetime.now(UTC)
    earlier = now - timedelta(days=2)

    note_a = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Alpha\n\nBody"),
        folder="Work",
    )
    note_b = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Beta\n\nBody"),
        folder="Archive/Old",
    )
    NotesService.update_pinned(db_session, "test_user", note_a.id, True)

    note_a.created_at = earlier
    note_a.updated_at = earlier
    note_b.created_at = now
    note_b.updated_at = now
    db_session.commit()

    pinned_notes = NotesService.list_notes(
        db_session, "test_user", NoteFilters(pinned=True)
    )
    assert any(n.id == note_a.id for n in pinned_notes)

    archived_notes = NotesService.list_notes(
        db_session, "test_user", NoteFilters(archived=True)
    )
    assert any(n.id == note_b.id for n in archived_notes)

    active_notes = NotesService.list_notes(
        db_session, "test_user", NoteFilters(archived=False)
    )
    assert all(n.id != note_b.id for n in active_notes)

    filtered = NotesService.list_notes(
        db_session, "test_user", NoteFilters(folder="Work", title_search="Alpha")
    )
    assert len(filtered) == 1
    assert filtered[0].id == note_a.id


def test_archived_summary(db_session):
    now = datetime.now(UTC)
    archived_at = now - timedelta(hours=2)

    archived_note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Archived\n\nBody"),
        folder="Archive/Old",
    )
    NotesService.create_note(
        db_session,
        "test_user",
        _document("# Active\n\nBody"),
        folder="Work",
    )

    archived_note.updated_at = archived_at
    db_session.commit()

    summary = NotesService.archived_summary(db_session, "test_user")

    assert summary["archived_count"] == 1
    assert summary["archived_last_updated"] is not None
    summary_ts = datetime.fromisoformat(summary["archived_last_updated"])
    assert summary_ts.astimezone(UTC) == archived_at


def test_soft_delete_note_clears_pinned_state(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Delete Me\n\nBody"),
    )
    NotesService.update_pinned(db_session, "test_user", note.id, True)

    deleted = NotesService.soft_delete_note(db_session, "test_user", note.id)

    assert deleted is not None
    assert deleted.deleted_at is not None
    assert deleted.pinned is False
    assert deleted.pinned_order is None


def test_update_note_conflict(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Title\n\nBody"),
    )
    stale = note.updated_at - timedelta(seconds=10)

    with pytest.raises(ConflictError):
        NotesService.update_note(
            db_session,
            "test_user",
            note.id,
            _document("# Title\n\nUpdated"),
            client_updated_at=stale,
        )
