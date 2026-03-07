import os
import uuid
from datetime import UTC, datetime

from api.config import settings
from api.models.note import Note
from api.services.notes_document_types import note_document_from_plain_text

from tests.helpers import error_message

TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def _document_payload(plain_text: str) -> dict[str, object]:
    return {"document": note_document_from_plain_text(plain_text)}


def test_notes_search_requires_query(test_client):
    response = test_client.post(
        "/api/notes/search", params={"query": ""}, headers=_auth_headers()
    )
    assert response.status_code == 400
    assert error_message(response) == "query required"


def test_notes_search_matches_plain_text_cache(test_client):
    create_payload = _document_payload("# Searchable\n\nAlpha Needle Body")
    create = test_client.post(
        "/api/notes",
        json=create_payload,
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
    assert any(item["name"] == "Searchable" for item in payload.get("items", []))


def test_notes_create_folder_requires_path(test_client):
    response = test_client.post("/api/notes/folders", json={}, headers=_auth_headers())
    assert response.status_code == 400
    assert error_message(response) == "path required"


def test_notes_create_requires_document(test_client):
    response = test_client.post(
        "/api/notes",
        json={"plain_text": "missing document"},
        headers=_auth_headers(),
    )
    assert response.status_code == 400
    assert error_message(response) == "document required"


def test_notes_get_invalid_id(test_client):
    response = test_client.get("/api/notes/not-a-uuid", headers=_auth_headers())
    assert response.status_code == 422
    detail = response.json().get("detail", [])
    assert detail
    assert "uuid" in detail[0].get("msg", "").lower()


def test_notes_get_success(test_client, test_db):
    note_id = uuid.uuid4()
    document = note_document_from_plain_text("# Sample Note\n\nBody")
    note = Note(
        id=note_id,
        user_id=TEST_USER_ID,
        title="Sample Note",
        document=document,
        document_version=1,
        plain_text="# Sample Note\n\nBody",
        folder_path="",
        pinned=False,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(note)
    test_db.commit()

    response = test_client.get(f"/api/notes/{note_id}", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Sample Note"
    assert body["name"] == "Sample Note"
    assert body["path"] == str(note_id)
    assert body["folder"] == ""
    assert body["pinned"] is False
    assert body["document"] == document
    assert body["document_version"] == 1


def test_notes_download_handles_unicode_filename(test_client, test_db):
    note_id = uuid.uuid4()
    note = Note(
        id=note_id,
        user_id=TEST_USER_ID,
        title="Codex Log🦞",
        document=note_document_from_plain_text("# Codex Log\n\nBody"),
        document_version=1,
        plain_text="# Codex Log\n\nBody",
        folder_path="",
        pinned=False,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(note)
    test_db.commit()

    response = test_client.get(
        f"/api/notes/{note_id}/download", headers=_auth_headers()
    )
    assert response.status_code == 200
    assert response.text == "# Codex Log\n\nBody"
    header = response.headers["content-disposition"]
    assert 'filename="Codex Log.txt"' in header
    assert "filename*=UTF-8''Codex%20Log%F0%9F%A6%9E.txt" in header
    assert "🦞" not in header


def test_notes_create_and_update_derive_title_from_plain_text(test_client):
    created_content = "# Title\n\nBody"
    create_payload = _document_payload(created_content)
    create = test_client.post(
        "/api/notes",
        json=create_payload,
        headers=_auth_headers(),
    )
    assert create.status_code == 200
    created_payload = create.json()
    note_id = created_payload["id"]
    assert created_payload["title"] == "Title"
    assert created_payload["plain_text"] == created_content
    assert created_payload["document"] == note_document_from_plain_text(created_content)
    assert created_payload["folder"] == ""
    assert created_payload["pinned"] is False

    updated_content = "\n\nUpdated Title\nUpdated body"
    update_payload = _document_payload(updated_content)
    update = test_client.patch(
        f"/api/notes/{note_id}",
        json=update_payload,
        headers=_auth_headers(),
    )
    assert update.status_code == 200
    updated_payload = update.json()
    assert updated_payload["title"] == "Updated Title"
    assert updated_payload["plain_text"] == updated_content
    assert updated_payload["document"] == note_document_from_plain_text(updated_content)
    assert updated_payload["folder"] == ""


def test_notes_rename_is_rejected(test_client):
    create_payload = _document_payload("# Title\n\nBody")
    create = test_client.post(
        "/api/notes",
        json=create_payload,
        headers=_auth_headers(),
    )
    assert create.status_code == 200
    note_id = create.json()["id"]

    rename = test_client.patch(
        f"/api/notes/{note_id}/rename",
        json={"newName": "Renamed Note"},
        headers=_auth_headers(),
    )
    assert rename.status_code == 400
    assert error_message(rename) == "Note titles are derived from note content"


def test_notes_create_rejects_explicit_title(test_client):
    response = test_client.post(
        "/api/notes",
        json={
            "document": note_document_from_plain_text("# Title\n\nBody"),
            "title": "Manual Title",
        },
        headers=_auth_headers(),
    )
    assert response.status_code == 400
    assert error_message(response) == "Note titles are derived from note content"


def test_notes_update_requires_document(test_client):
    create_payload = _document_payload("# Title\n\nBody")
    create = test_client.post(
        "/api/notes",
        json=create_payload,
        headers=_auth_headers(),
    )
    assert create.status_code == 200
    note_id = create.json()["id"]

    response = test_client.patch(
        f"/api/notes/{note_id}",
        json={"plain_text": "# Title\n\nUpdated"},
        headers=_auth_headers(),
    )
    assert response.status_code == 400
    assert error_message(response) == "document required"


def test_notes_pin_move_archive(test_client, test_db):
    create_payload = _document_payload("# Title\n\nBody")
    create = test_client.post(
        "/api/notes",
        json=create_payload,
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
    assert moved.folder_path == "Inbox"
    assert moved.pinned is False
    assert moved.pinned_order is None

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
    assert archived.folder_path == "Archive"
    assert archived.pinned is False
    assert archived.pinned_order is None


def test_notes_delete_unpins_note(test_client, test_db):
    create_payload = _document_payload("# Delete Me\n\nBody")
    create = test_client.post(
        "/api/notes",
        json=create_payload,
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
    assert deleted.pinned is False
    assert deleted.pinned_order is None


def test_notes_sync_returns_updates_items_payload(test_client):
    create_payload = _document_payload("# Sync\n\nBody")
    create = test_client.post(
        "/api/notes",
        json=create_payload,
        headers=_auth_headers(),
    )
    assert create.status_code == 200
    note_id = create.json()["id"]

    response = test_client.post(
        "/api/notes/sync",
        json={
            "last_sync": None,
            "operations": [
                {
                    "operationId": "op-rename-1",
                    "op": "rename",
                    "id": note_id,
                    "title": "Renamed by Sync",
                }
            ],
        },
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["applied"] == ["op-rename-1"]
    assert "notes" not in payload["updates"]
    assert "items" in payload["updates"]
    assert any(item["id"] == note_id for item in payload["updates"]["items"])
