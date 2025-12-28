from api.config import settings


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
