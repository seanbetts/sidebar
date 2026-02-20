"""Tests for the skills catalog API response shape."""

from api.config import settings
from tests.helpers import error_message


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_list_skills_includes_catalog_version_and_v2_fields(test_client) -> None:
    response = test_client.get("/api/skills", headers=_auth_headers())
    assert response.status_code == 200

    payload = response.json()
    assert payload["catalog_version"] == 2
    assert isinstance(payload["skills"], list)
    assert payload["skills"]

    by_id = {item["id"]: item for item in payload["skills"]}
    assert "files" in by_id
    assert "fs" not in by_id
    assert by_id["files"]["legacy_ids"] == ["fs"]
    assert by_id["files"]["tier"] == "standard"
    assert by_id["files"]["installable"] is False

    assert "audio-transcribe" in by_id
    assert by_id["audio-transcribe"]["tier"] == "store"
    assert by_id["audio-transcribe"]["provider_dependency"] == "openai"
    assert by_id["audio-transcribe"]["credential_requirements"]


def test_install_store_skill_auto_enables_and_persists(test_client) -> None:
    install_response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert install_response.status_code == 200

    body = install_response.json()
    assert body["skill_id"] == "audio-transcribe"
    assert body["installed"] is True
    assert body["enabled"] is True
    assert "audio-transcribe" in body["enabled_skills"]
    assert "audio-transcribe" in body["installed_store_skills"]


def test_install_store_skill_is_idempotent(test_client) -> None:
    first = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert first.status_code == 200

    second = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert second.status_code == 200
    body = second.json()
    assert body["installed_store_skills"].count("audio-transcribe") == 1
    assert body["enabled_skills"].count("audio-transcribe") == 1


def test_install_store_skill_rejects_non_store_skill(test_client) -> None:
    response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "files"},
    )
    assert response.status_code == 400
    assert "not installable" in error_message(response)


def test_install_store_skill_rejects_unknown_skill_id(test_client) -> None:
    response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "not-a-skill"},
    )
    assert response.status_code == 400
    assert "Invalid skill ID" in error_message(response)
