from importlib import import_module
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from api.services.agent.skills.catalog import SkillCatalogService
from api.services.settings_service import (
    DEFAULT_ASSISTANT_IDENTITY,
    DEFAULT_ASSISTANT_SOUL,
    MAX_ASSISTANT_IDENTITY_NAME_CHARS,
    MAX_ASSISTANT_SOUL_TEXT_CHARS,
    SettingsService,
)
from api.services.user_ai_provider_settings_service import (
    UserAIProviderSettingsService,
)
from api.services.user_settings_service import UserSettingsService


def test_clean_updates_rejects_agent_owned_fields() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_updates(
            {
                "assistant_identity": {
                    "name": "Navigator",
                }
            }
        )
    assert exc_info.value.status_code == 400
    assert "settings has invalid fields: assistant_identity" in str(
        exc_info.value.detail
    )


def test_clean_agent_updates_trims_assistant_identity_fields() -> None:
    updates = {
        "assistant_identity": {
            "name": "  Navigator  ",
            "tone": "  Calm and clear.  ",
        }
    }

    cleaned = SettingsService.clean_agent_updates(updates)
    assert cleaned["assistant_identity"]["name"] == "Navigator"
    assert cleaned["assistant_identity"]["tone"] == "Calm and clear."


def test_clean_agent_updates_rejects_unknown_assistant_identity_fields() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_agent_updates(
            {
                "assistant_identity": {
                    "name": "Navigator",
                    "mode": "invalid",
                }
            }
        )
    assert exc_info.value.status_code == 400
    assert "assistant_identity has invalid fields" in str(exc_info.value.detail)


def test_clean_agent_updates_rejects_long_assistant_identity_name() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_agent_updates(
            {
                "assistant_identity": {
                    "name": "a" * (MAX_ASSISTANT_IDENTITY_NAME_CHARS + 1)
                }
            }
        )
    assert exc_info.value.status_code == 400
    assert "assistant_identity.name exceeds" in str(exc_info.value.detail)


def test_clean_agent_updates_rejects_user_owned_fields() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_agent_updates({"communication_style": "brief"})
    assert exc_info.value.status_code == 400
    assert "agent_settings has invalid fields: communication_style" in str(
        exc_info.value.detail
    )


def test_clean_agent_updates_trims_assistant_soul_fields() -> None:
    updates = {
        "assistant_soul": {
            "purpose": "  Help with durable progress.  ",
            "success_signals": "  Fewer clarifications needed.  ",
        }
    }

    cleaned = SettingsService.clean_agent_updates(updates)
    assert cleaned["assistant_soul"]["purpose"] == "Help with durable progress."
    assert (
        cleaned["assistant_soul"]["success_signals"] == "Fewer clarifications needed."
    )


def test_clean_agent_updates_rejects_unknown_assistant_soul_fields() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_agent_updates(
            {
                "assistant_soul": {
                    "purpose": "Help clearly.",
                    "mode": "invalid",
                }
            }
        )
    assert exc_info.value.status_code == 400
    assert "assistant_soul has invalid fields" in str(exc_info.value.detail)


def test_clean_agent_updates_rejects_long_assistant_soul_field() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_agent_updates(
            {"assistant_soul": {"purpose": "a" * (MAX_ASSISTANT_SOUL_TEXT_CHARS + 1)}}
        )
    assert exc_info.value.status_code == 400
    assert "assistant_soul.purpose exceeds" in str(exc_info.value.detail)


def test_build_response_resolves_default_assistant_identity() -> None:
    payload = SettingsService.build_response(settings_record=None, user_id="user-1")
    assert payload["assistant_identity"] == DEFAULT_ASSISTANT_IDENTITY
    assert payload["assistant_soul"] == DEFAULT_ASSISTANT_SOUL


def test_build_response_uses_assistant_identity_overrides(monkeypatch) -> None:
    monkeypatch.setattr(
        SettingsService,
        "_resolve_enabled_skills",
        staticmethod(lambda settings_record: []),
    )
    settings_record = SimpleNamespace(
        communication_style=None,
        working_relationship=None,
        name=None,
        job_title=None,
        employer=None,
        date_of_birth=None,
        gender=None,
        pronouns=None,
        location=None,
        profile_image_path=None,
        enabled_skills=None,
        assistant_identity={
            "name": "Navigator",
            "tone": "Calm and technical.",
            "values": "Accuracy and focus.",
            "boundaries": "No fabricated claims.",
        },
    )

    payload = SettingsService.build_response(
        settings_record=settings_record, user_id="user-1"
    )
    assert payload["assistant_identity"]["name"] == "Navigator"
    assert payload["assistant_identity"]["tone"] == "Calm and technical."
    assert payload["assistant_identity"]["values"] == "Accuracy and focus."
    assert payload["assistant_identity"]["boundaries"] == "No fabricated claims."


def test_build_response_includes_agent_field_metadata() -> None:
    settings_record = SimpleNamespace(
        communication_style=None,
        working_relationship=None,
        name=None,
        job_title=None,
        employer=None,
        date_of_birth=None,
        gender=None,
        pronouns=None,
        location=None,
        profile_image_path=None,
        enabled_skills=None,
        assistant_identity={
            "name": "Navigator",
            "_meta": {
                "updated_at": "2026-02-17T10:00:00Z",
                "version": 2,
                "reason": "User renamed the assistant.",
            },
        },
        assistant_soul={
            "purpose": "Help with deliberate execution.",
            "_meta": {
                "updated_at": "2026-02-17T10:05:00Z",
                "version": 1,
                "reason": "Initial bootstrap.",
            },
        },
    )
    payload = SettingsService.build_response(
        settings_record=settings_record, user_id="user-1"
    )
    assert payload["assistant_identity_meta"]["version"] == 2
    assert payload["assistant_soul_meta"]["version"] == 1


def test_update_agent_settings_is_scoped_per_user(test_db, monkeypatch) -> None:
    monkeypatch.setattr(
        SettingsService,
        "_resolve_enabled_skills",
        staticmethod(lambda _settings_record: []),
    )

    user_a = "user-a"
    user_b = "user-b"

    SettingsService.update_agent_settings(
        test_db,
        user_a,
        {
            "assistant_identity": {"name": "Navigator A"},
            "assistant_soul": {"purpose": "Purpose A"},
        },
        reason="Bootstrap A",
    )
    SettingsService.update_agent_settings(
        test_db,
        user_b,
        {
            "assistant_identity": {"name": "Navigator B"},
            "assistant_soul": {"purpose": "Purpose B"},
        },
        reason="Bootstrap B",
    )

    SettingsService.update_agent_settings(
        test_db,
        user_a,
        {"assistant_soul": {"purpose": "Purpose A2"}},
        reason="Refine A",
    )

    payload_a = SettingsService.get_settings(test_db, user_a)
    payload_b = SettingsService.get_settings(test_db, user_b)

    assert payload_a["assistant_identity"]["name"] == "Navigator A"
    assert payload_b["assistant_identity"]["name"] == "Navigator B"
    assert payload_a["assistant_soul"]["purpose"] == "Purpose A2"
    assert payload_b["assistant_soul"]["purpose"] == "Purpose B"
    assert payload_a["assistant_soul_meta"]["version"] == 2
    assert payload_b["assistant_soul_meta"]["version"] == 1


def test_clean_updates_forces_required_skills(monkeypatch) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "files",
                    "name": "Files",
                    "description": "File access",
                    "category": "Documents",
                    "tier": "standard",
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "name": "Assistant Identity",
                    "description": "Assistant identity controls",
                    "category": "System",
                    "tier": "required",
                    "user_toggleable": False,
                },
            ]
        ),
    )

    cleaned = SettingsService.clean_updates({"enabled_skills": ["files"]})
    assert cleaned["enabled_skills"] == ["files", "assistant-identity"]


def test_clean_updates_rejects_legacy_fs_skill_id(monkeypatch) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {"id": "files", "user_toggleable": True},
                {"id": "assistant-identity", "user_toggleable": False},
            ]
        ),
    )

    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_updates({"enabled_skills": ["fs"]})

    assert exc_info.value.status_code == 400
    assert "Invalid skills: fs" in str(exc_info.value.detail)


def test_resolve_enabled_skills_forces_required_skills(monkeypatch) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "files",
                    "name": "Files",
                    "description": "File access",
                    "category": "Documents",
                    "tier": "standard",
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "name": "Assistant Identity",
                    "description": "Assistant identity controls",
                    "category": "System",
                    "tier": "required",
                    "user_toggleable": False,
                },
            ]
        ),
    )
    settings_record = SimpleNamespace(enabled_skills=["files"])

    resolved = SettingsService._resolve_enabled_skills(settings_record)
    assert resolved == ["files", "assistant-identity"]


def test_resolve_enabled_skills_defaults_to_required_and_standard_only(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "files",
                    "tier": "standard",
                    "default_enabled": True,
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "tier": "required",
                    "default_enabled": True,
                    "user_toggleable": False,
                },
                {
                    "id": "audio-transcribe",
                    "tier": "store",
                    "default_enabled": False,
                    "user_toggleable": True,
                },
            ]
        ),
    )
    settings_record = SimpleNamespace(enabled_skills=None, installed_store_skills=None)

    resolved = SettingsService._resolve_enabled_skills(settings_record)
    assert resolved == ["files", "assistant-identity"]


def test_resolve_enabled_skills_filters_uninstalled_store_skill(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "files",
                    "tier": "standard",
                    "default_enabled": True,
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "tier": "required",
                    "default_enabled": True,
                    "user_toggleable": False,
                },
                {
                    "id": "audio-transcribe",
                    "tier": "store",
                    "default_enabled": False,
                    "user_toggleable": True,
                },
            ]
        ),
    )
    settings_record = SimpleNamespace(
        enabled_skills=["files", "audio-transcribe"],
        installed_store_skills=[],
    )

    resolved = SettingsService._resolve_enabled_skills(settings_record)
    assert resolved == ["files", "assistant-identity"]


def test_resolve_installed_store_skills_filters_non_store_entries(monkeypatch) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {"id": "files", "tier": "standard"},
                {"id": "prompt-preview", "tier": "standard"},
                {"id": "settings-other-preferences", "tier": "standard"},
                {"id": "audio-transcribe", "tier": "store"},
                {"id": "youtube-transcribe", "tier": "store"},
            ]
        ),
    )
    settings_record = SimpleNamespace(
        installed_store_skills=[
            "audio-transcribe",
            "files",
            "unknown-skill",
            "prompt-preview",
            "settings-other-preferences",
            "youtube-transcribe",
        ]
    )

    resolved = SettingsService._resolve_installed_store_skills(settings_record)
    assert resolved == ["audio-transcribe", "youtube-transcribe"]


def test_get_settings_prefers_normalized_skill_states_over_legacy_arrays(
    test_db,
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "files",
                    "tier": "standard",
                    "default_enabled": True,
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "tier": "required",
                    "default_enabled": True,
                    "user_toggleable": False,
                },
                {
                    "id": "assistant-soul",
                    "tier": "required",
                    "default_enabled": True,
                    "user_toggleable": False,
                },
                {
                    "id": "audio-transcribe",
                    "tier": "store",
                    "default_enabled": False,
                    "user_toggleable": True,
                    "credential_requirements": [
                        {
                            "provider": "openai",
                            "key_kind": "api_key",
                            "required": True,
                        }
                    ],
                },
            ]
        ),
    )
    user_id = "runtime-state-precedence-user"
    UserSettingsService.upsert_settings(
        test_db,
        user_id,
        enabled_skills=["files", "assistant-identity", "assistant-soul"],
        installed_store_skills=[],
    )
    skill_state_service = _skill_state_service()
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="files",
        enabled=False,
        installed=False,
        commit=False,
    )
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="assistant-identity",
        enabled=True,
        installed=False,
        commit=False,
    )
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="assistant-soul",
        enabled=True,
        installed=False,
        commit=False,
    )
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        enabled=True,
        installed=True,
        commit=True,
    )

    payload = SettingsService.get_settings(test_db, user_id)

    assert "files" not in payload["enabled_skills"]
    assert "audio-transcribe" in payload["enabled_skills"]
    assert payload["installed_store_skills"] == ["audio-transcribe"]


def test_get_settings_filters_uninstalled_store_skills_from_normalized_state(
    test_db,
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "files",
                    "tier": "standard",
                    "default_enabled": True,
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "tier": "required",
                    "default_enabled": True,
                    "user_toggleable": False,
                },
                {
                    "id": "assistant-soul",
                    "tier": "required",
                    "default_enabled": True,
                    "user_toggleable": False,
                },
                {
                    "id": "audio-transcribe",
                    "tier": "store",
                    "default_enabled": False,
                    "user_toggleable": True,
                    "credential_requirements": [
                        {
                            "provider": "openai",
                            "key_kind": "api_key",
                            "required": True,
                        }
                    ],
                },
            ]
        ),
    )
    user_id = "runtime-state-uninstalled-store-user"
    UserSettingsService.upsert_settings(
        test_db,
        user_id,
        enabled_skills=[
            "files",
            "assistant-identity",
            "assistant-soul",
            "audio-transcribe",
        ],
        installed_store_skills=["audio-transcribe"],
    )
    skill_state_service = _skill_state_service()
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="files",
        enabled=True,
        installed=False,
        commit=False,
    )
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="assistant-identity",
        enabled=True,
        installed=False,
        commit=False,
    )
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="assistant-soul",
        enabled=True,
        installed=False,
        commit=False,
    )
    skill_state_service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        enabled=True,
        installed=False,
        commit=True,
    )

    payload = SettingsService.get_settings(test_db, user_id)

    assert "audio-transcribe" not in payload["enabled_skills"]
    assert payload["installed_store_skills"] == []


def _skill_state_service():
    try:
        module = import_module("api.services.capabilities.skill_state_service")
    except ModuleNotFoundError:
        pytest.fail(
            "Skill state service module missing: "
            "api.services.capabilities.skill_state_service"
        )
    service = getattr(module, "SkillStateService", None)
    if service is None:
        pytest.fail("SkillStateService class missing from capability service module")
    return service


def test_update_settings_mirrors_legacy_skill_selection_into_skill_states(
    test_db,
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "files",
                    "tier": "standard",
                    "default_enabled": True,
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "tier": "required",
                    "default_enabled": True,
                    "user_toggleable": False,
                },
                {
                    "id": "audio-transcribe",
                    "tier": "store",
                    "default_enabled": False,
                    "user_toggleable": True,
                },
            ]
        ),
    )

    SettingsService.update_settings(
        test_db,
        "settings-skill-state-user",
        {"enabled_skills": ["files"]},
    )

    states = _skill_state_service().list_active_skill_states(
        test_db,
        "settings-skill-state-user",
    )
    by_skill = {state.skill_id: state for state in states}
    assert by_skill["files"].enabled is True
    assert by_skill["assistant-identity"].enabled is True
    assert by_skill["files"].installed is False


def test_clean_updates_accepts_ai_provider_fields() -> None:
    cleaned = SettingsService.clean_updates({"ai_primary_provider": "  OPENAI  "})
    assert cleaned["ai_primary_provider"] == "openai"


def test_clean_updates_rejects_invalid_ai_provider() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_updates({"ai_primary_provider": "unknown-provider"})
    assert exc_info.value.status_code == 400
    assert "Invalid ai_primary_provider" in str(exc_info.value.detail)


def test_build_response_defaults_ai_provider_policy() -> None:
    payload = SettingsService.build_response(settings_record=None, user_id="user-1")
    assert payload["ai_primary_provider"] is None


def test_get_settings_includes_primary_provider_key_status(test_db) -> None:
    user_id = "provider-status-user"
    SettingsService.update_settings(
        test_db,
        user_id,
        {"ai_primary_provider": "openai"},
    )
    UserAIProviderSettingsService.upsert_provider_key(
        test_db,
        user_id,
        provider="openai",
        api_key="sk-test-openai-4321",
    )

    payload = SettingsService.get_settings(test_db, user_id)
    payload = UserAIProviderSettingsService.attach_primary_provider_key_status(
        test_db,
        user_id=user_id,
        payload=payload,
    )
    assert payload["ai_primary_provider"] == "openai"
    assert payload["ai_primary_provider_has_key"] is True
    assert payload["ai_primary_provider_key_last4"] == "4321"
