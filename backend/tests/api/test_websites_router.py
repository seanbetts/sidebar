from datetime import datetime, timezone
import uuid

from api.config import settings
from api.db.dependencies import DEFAULT_USER_ID
from api.models.website import Website


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_websites_search_requires_query(test_client):
    response = test_client.post("/api/websites/search", params={"query": ""}, headers=_auth_headers())
    assert response.status_code == 400
    assert response.json()["detail"] == "query required"


def test_websites_save_requires_url(test_client):
    response = test_client.post("/api/websites/save", json={}, headers=_auth_headers())
    assert response.status_code == 400
    assert response.json()["detail"] == "url required"


def test_websites_get_success(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=DEFAULT_USER_ID,
        url="https://example.com",
        url_full="https://example.com",
        domain="example.com",
        title="Example",
        content="Example content",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    test_db.add(website)
    test_db.commit()

    response = test_client.get(f"/api/websites/{website_id}", headers=_auth_headers())
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(website_id)
    assert body["content"] == "Example content"


def test_websites_pin_rename_archive(test_client, test_db):
    website_id = uuid.uuid4()
    website = Website(
        id=website_id,
        user_id=DEFAULT_USER_ID,
        url="https://example.org",
        url_full="https://example.org",
        domain="example.org",
        title="Example Org",
        content="Example content",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    test_db.add(website)
    test_db.commit()

    pin = test_client.patch(
        f"/api/websites/{website_id}/pin",
        json={"pinned": True},
        headers=_auth_headers(),
    )
    assert pin.status_code == 200

    rename = test_client.patch(
        f"/api/websites/{website_id}/rename",
        json={"title": "Renamed"},
        headers=_auth_headers(),
    )
    assert rename.status_code == 200

    archive = test_client.patch(
        f"/api/websites/{website_id}/archive",
        json={"archived": True},
        headers=_auth_headers(),
    )
    assert archive.status_code == 200
