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


def test_files_create_folder_and_tree(test_client):
    create = test_client.post(
        "/api/files/folder",
        json={"basePath": "documents", "path": "Folder"},
        headers=_auth_headers(),
    )
    assert create.status_code == 200

    tree = test_client.get("/api/files/tree", params={"basePath": "documents"}, headers=_auth_headers())
    assert tree.status_code == 200
    names = [item["name"] for item in tree.json()["children"]]
    assert "Folder" in names


def test_files_update_and_get_content(test_client):
    update = test_client.post(
        "/api/files/content",
        json={"basePath": "documents", "path": "demo.txt", "content": "hello"},
        headers=_auth_headers(),
    )
    assert update.status_code == 200

    get_content = test_client.get(
        "/api/files/content",
        params={"basePath": "documents", "path": "demo.txt"},
        headers=_auth_headers(),
    )
    assert get_content.status_code == 200
    assert get_content.json()["content"] == "hello"
