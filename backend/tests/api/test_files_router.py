from api.config import settings


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_files_search_requires_query(test_client):
    response = test_client.post("/api/files/search", params={"query": ""}, headers=_auth_headers())
    assert response.status_code == 400
    assert response.json()["detail"] == "query required"


def test_files_delete_rejects_root(test_client):
    response = test_client.post("/api/files/delete", json={"path": "/"}, headers=_auth_headers())
    assert response.status_code == 400
    assert response.json()["detail"] == "Cannot delete root directory"
