import os
import uuid
from datetime import UTC, datetime

from api.config import settings
from api.models.note import Note

from tests.helpers import error_message

TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_notes_search_requires_query(test_client):
    response = test_client.post(
        "/api/notes/search", params={"query": ""}, headers=_auth_headers()
    )
    assert response.status_code == 400
    assert error_message(response) == "query required"


def test_notes_search_matches_plain_text_cache(test_client):
    create = test_client.post(
        "/api/notes",
        json={"title": "Searchable", "content": "# Searchable\n\nAlpha Needle Body"},
        headers=_auth_headers(),
    )
    assert create.status_code == 200

    response = test_client.post(
        "/api/notes/search",
        json={"query": "Needle", "limit": 10},
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    payload = response.json()
    assert any(item["name"] == "Searchable.md" for item in payload.get("items", []))


def test_notes_create_folder_requires_path(test_client):
    response = test_client.post("/api/notes/folders", json={}, headers=_auth_headers())
    assert response.status_code == 400
    assert error_message(response) == "path required"


def test_notes_get_invalid_id(test_client):
    response = test_client.get("/api/notes/not-a-uuid", headers=_auth_headers())
    assert response.status_code == 422
    detail = response.json().get("detail", [])
    assert detail
    assert "uuid" in detail[0].get("msg", "").lower()


def test_notes_get_success(test_client, test_db):
    note_id = uuid.uuid4()
    note = Note(
        id=note_id,
        user_id=TEST_USER_ID,
        title="Sample Note",
        content="# Sample Note\n\nBody",
        metadata_={"folder": "", "pinned": False},
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(note)
    test_db.commit()

    response = test_client.get(f"/api/notes/{note_id}", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["path"] == str(note_id)
    assert "content" in body


def test_notes_download_handles_unicode_filename(test_client, test_db):
    note_id = uuid.uuid4()
    note = Note(
        id=note_id,
        user_id=TEST_USER_ID,
        title="Codex Log🦞",
        content="# Codex Log\n\nBody",
        metadata_={"folder": "", "pinned": False},
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(note)
    test_db.commit()

    response = test_client.get(f"/api/notes/{note_id}/download", headers=_auth_headers())
    assert response.status_code == 200
    assert response.text == "# Codex Log\n\nBody"
    header = response.headers["content-disposition"]
    assert 'filename="Codex Log.md"' in header
    assert "filename*=UTF-8''Codex%20Log%F0%9F%A6%9E.md" in header
    assert "🦞" not in header


def test_notes_create_update_and_rename(test_client):
    created_content = "# Title\n\nBody"
    create = test_client.post(
        "/api/notes",
        json={"content": created_content},
        headers=_auth_headers(),
    )
    assert create.status_code == 200
    created_payload = create.json()
    note_id = created_payload["id"]
    assert created_payload["plain_text"] == created_content
    assert created_payload["content_format"] == "rtf"

    updated_content = "# Title\n\nUpdated"
    update = test_client.patch(
        f"/api/notes/{note_id}",
        json={"content": updated_content},
        headers=_auth_headers(),
    )
    assert update.status_code == 200
    updated_payload = update.json()
    assert updated_payload["plain_text"] == updated_content
    assert updated_payload["content_format"] == "rtf"

    rename = test_client.patch(
        f"/api/notes/{note_id}/rename",
        json={"newName": "Renamed Note.md"},
        headers=_auth_headers(),
    )
    assert rename.status_code == 200


def test_notes_pin_move_archive(test_client, test_db):
    create = test_client.post(
        "/api/notes",
        json={"content": "# Title\n\nBody"},
        headers=_auth_headers(),
    )
    note_id = create.json()["id"]

    pin = test_client.patch(
        f"/api/notes/{note_id}/pin",
        json={"pinned": True},
        headers=_auth_headers(),
    )
    assert pin.status_code == 200

    move = test_client.patch(
        f"/api/notes/{note_id}/move",
        json={"folder": "Inbox"},
        headers=_auth_headers(),
    )
    assert move.status_code == 200
    moved = test_db.query(Note).filter(Note.id == uuid.UUID(note_id)).first()
    assert moved is not None
    moved_metadata = moved.metadata_ or {}
    assert moved_metadata.get("folder") == "Inbox"
    assert moved_metadata.get("pinned") is False
    assert moved_metadata.get("pinned_order") is None

    repin = test_client.patch(
        f"/api/notes/{note_id}/pin",
        json={"pinned": True},
        headers=_auth_headers(),
    )
    assert repin.status_code == 200

    archive = test_client.patch(
        f"/api/notes/{note_id}/archive",
        json={"archived": True},
        headers=_auth_headers(),
    )
    assert archive.status_code == 200
    test_db.expire_all()
    archived = test_db.query(Note).filter(Note.id == uuid.UUID(note_id)).first()
    assert archived is not None
    archived_metadata = archived.metadata_ or {}
    assert archived_metadata.get("folder") == "Archive"
    assert archived_metadata.get("pinned") is False
    assert archived_metadata.get("pinned_order") is None


def test_notes_delete_unpins_note(test_client, test_db):
    create = test_client.post(
        "/api/notes",
        json={"content": "# Delete Me\n\nBody"},
        headers=_auth_headers(),
    )
    note_id = create.json()["id"]

    pin = test_client.patch(
        f"/api/notes/{note_id}/pin",
        json={"pinned": True},
        headers=_auth_headers(),
    )
    assert pin.status_code == 200

    delete = test_client.delete(f"/api/notes/{note_id}", headers=_auth_headers())
    assert delete.status_code == 200

    test_db.expire_all()
    deleted = test_db.query(Note).filter(Note.id == uuid.UUID(note_id)).first()
    assert deleted is not None
    assert deleted.deleted_at is not None
    deleted_metadata = deleted.metadata_ or {}
    assert deleted_metadata.get("pinned") is False
    assert deleted_metadata.get("pinned_order") is None
