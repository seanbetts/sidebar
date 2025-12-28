from datetime import datetime, timezone
import uuid

from api.config import settings
from api.db.dependencies import DEFAULT_USER_ID
from api.models.note import Note


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_notes_search_requires_query(test_client):
    response = test_client.post("/api/notes/search", params={"query": ""}, headers=_auth_headers())
    assert response.status_code == 400
    assert response.json()["detail"] == "query required"


def test_notes_create_folder_requires_path(test_client):
    response = test_client.post("/api/notes/folders", json={}, headers=_auth_headers())
    assert response.status_code == 400
    assert response.json()["detail"] == "path required"


def test_notes_get_invalid_id(test_client):
    response = test_client.get("/api/notes/not-a-uuid", headers=_auth_headers())
    assert response.status_code == 400
    assert "Invalid note id" in response.json()["detail"]


def test_notes_get_success(test_client, test_db):
    note_id = uuid.uuid4()
    note = Note(
        id=note_id,
        user_id=DEFAULT_USER_ID,
        title="Sample Note",
        content="# Sample Note\n\nBody",
        metadata_={"folder": "", "pinned": False},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    test_db.add(note)
    test_db.commit()

    response = test_client.get(f"/api/notes/{note_id}", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["path"] == str(note_id)
    assert "content" in body


def test_notes_create_update_and_rename(test_client):
    create = test_client.post(
        "/api/notes",
        json={"content": "# Title\n\nBody"},
        headers=_auth_headers(),
    )
    assert create.status_code == 200
    note_id = create.json()["id"]

    update = test_client.patch(
        f"/api/notes/{note_id}",
        json={"content": "# Title\n\nUpdated"},
        headers=_auth_headers(),
    )
    assert update.status_code == 200

    rename = test_client.patch(
        f"/api/notes/{note_id}/rename",
        json={"newName": "Renamed Note.md"},
        headers=_auth_headers(),
    )
    assert rename.status_code == 200


def test_notes_pin_move_archive(test_client):
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

    archive = test_client.patch(
        f"/api/notes/{note_id}/archive",
        json={"archived": True},
        headers=_auth_headers(),
    )
    assert archive.status_code == 200
