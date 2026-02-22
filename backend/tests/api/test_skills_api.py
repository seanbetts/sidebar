"""Tests for the skills catalog API response shape."""

from api.config import settings
from tests.helpers import error_message


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def _seed_openai_provider_key(test_client, api_key: str = "sk-test-openai-1234") -> None:
    response = test_client.put(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        json={"provider": "openai", "api_key": api_key},
    )
    assert response.status_code == 200


def test_list_skills_includes_catalog_version_and_v2_fields(test_client) -> None:
    response = test_client.get("/api/skills", headers=_auth_headers())
    assert response.status_code == 200

    payload = response.json()
    assert payload["catalog_version"] == 8
    assert isinstance(payload["skills"], list)
    assert payload["skills"]

    by_id = {item["id"]: item for item in payload["skills"]}
    assert "files" in by_id
    assert "fs" not in by_id
    assert by_id["files"]["legacy_ids"] == []
    assert by_id["files"]["tier"] == "standard"
    assert by_id["files"]["installable"] is False

    assert "audio-transcribe" in by_id
    assert "skill-creator" not in by_id
    assert by_id["audio-transcribe"]["tier"] == "store"
    assert by_id["audio-transcribe"]["provider_dependency"] == "openai"
    assert by_id["audio-transcribe"]["credential_requirements"]
    assert isinstance(by_id["audio-transcribe"]["long_description"], str)
    assert isinstance(by_id["audio-transcribe"]["how_it_works"], str)
    assert by_id["audio-transcribe"]["requirements"] == []
    assert by_id["audio-transcribe"]["version"] == "1.0.0"
    assert by_id["audio-transcribe"]["updated_at"] == "2026-02-22"
    assert by_id["audio-transcribe"]["install_count"] is None
    assert by_id["audio-transcribe"]["upvotes"] is None
    assert by_id["audio-transcribe"]["downvotes"] is None
    assert by_id["audio-transcribe"]["current_user_vote"] is None
    assert by_id["prompt-preview"]["tier"] == "standard"
    assert by_id["prompt-preview"]["installable"] is False
    assert by_id["settings-other-preferences"]["tier"] == "standard"
    assert by_id["settings-other-preferences"]["installable"] is False
    assert by_id["settings-other-preferences"]["name"] == "Settings"
    assert by_id["product-feedback"]["tier"] == "standard"
    assert by_id["product-feedback"]["installable"] is False


def test_install_store_skill_auto_enables_and_persists(test_client) -> None:
    _seed_openai_provider_key(test_client)

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
    _seed_openai_provider_key(test_client)

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


def test_install_store_skill_rejects_when_required_key_missing(test_client) -> None:
    delete_status = test_client.delete(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        params={"provider": "openai"},
    )
    assert delete_status.status_code == 200

    response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert response.status_code == 400
    body = response.json()["error"]
    assert body["message"] == "Skill install requires provider API key"
    assert body["details"]["error_type"] == "SKILL_CREDENTIAL_REQUIRED"
    assert body["details"]["skill_id"] == "audio-transcribe"
    assert body["details"]["required_providers"] == ["openai"]
    assert body["details"]["missing_requirements"] == [
        {
            "provider": "openai",
            "key_kind": "api_key",
            "required": True,
        }
    ]


def test_install_store_skill_accepts_install_time_provider_key(test_client) -> None:
    install_response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={
            "skill_id": "audio-transcribe",
            "provider_keys": [
                {"provider": "openai", "api_key": "sk-test-openai-install-9876"}
            ],
        },
    )
    assert install_response.status_code == 200
    body = install_response.json()
    assert body["installed"] is True
    assert body["enabled"] is True

    key_status = test_client.get(
        "/api/settings/ai/provider-key",
        headers=_auth_headers(),
        params={"provider": "openai"},
    )
    assert key_status.status_code == 200
    status_body = key_status.json()
    assert status_body["has_key"] is True
    assert status_body["key_last4"] == "9876"


def test_install_store_skill_rejects_unexpected_provider_key(test_client) -> None:
    response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={
            "skill_id": "audio-transcribe",
            "provider_keys": [
                {"provider": "anthropic", "api_key": "sk-ant-key-12345678"}
            ],
        },
    )
    assert response.status_code == 400
    body = response.json()["error"]
    assert body["message"] == "Unexpected provider key for skill install"
    assert body["details"]["error_type"] == "SKILL_CREDENTIAL_UNEXPECTED_PROVIDER"
    assert body["details"]["skill_id"] == "audio-transcribe"
    assert body["details"]["required_providers"] == ["openai"]
    assert body["details"]["unexpected_providers"] == ["anthropic"]


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


def test_uninstall_store_skill_removes_install_and_enabled_state(test_client) -> None:
    _seed_openai_provider_key(test_client)
    install_response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert install_response.status_code == 200

    uninstall_response = test_client.post(
        "/api/skills/store/uninstall",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert uninstall_response.status_code == 200
    body = uninstall_response.json()
    assert body["skill_id"] == "audio-transcribe"
    assert body["installed"] is False
    assert body["enabled"] is False
    assert "audio-transcribe" not in body["installed_store_skills"]
    assert "audio-transcribe" not in body["enabled_skills"]


def test_uninstall_store_skill_is_idempotent(test_client) -> None:
    _seed_openai_provider_key(test_client)
    install_response = test_client.post(
        "/api/skills/store/install",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert install_response.status_code == 200

    first = test_client.post(
        "/api/skills/store/uninstall",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert first.status_code == 200

    second = test_client.post(
        "/api/skills/store/uninstall",
        headers=_auth_headers(),
        json={"skill_id": "audio-transcribe"},
    )
    assert second.status_code == 200
    body = second.json()
    assert body["installed_store_skills"].count("audio-transcribe") == 0
    assert body["enabled_skills"].count("audio-transcribe") == 0


def test_uninstall_store_skill_rejects_unknown_skill_id(test_client) -> None:
    response = test_client.post(
        "/api/skills/store/uninstall",
        headers=_auth_headers(),
        json={"skill_id": "not-a-skill"},
    )
    assert response.status_code == 400
    assert "Invalid skill ID" in error_message(response)
