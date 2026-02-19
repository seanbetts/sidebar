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
    assert cleaned["assistant_soul"]["success_signals"] == "Fewer clarifications needed."


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
    payload = SettingsService.build_response(settings_record=settings_record, user_id="user-1")
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
                    "id": "fs",
                    "name": "Files",
                    "description": "File access",
                    "category": "Documents",
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "name": "Assistant Identity",
                    "description": "Assistant identity controls",
                    "category": "System",
                    "user_toggleable": False,
                },
            ]
        ),
    )

    cleaned = SettingsService.clean_updates({"enabled_skills": ["fs"]})
    assert cleaned["enabled_skills"] == ["fs", "assistant-identity"]


def test_resolve_enabled_skills_forces_required_skills(monkeypatch) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(
            lambda _skills_dir: [
                {
                    "id": "fs",
                    "name": "Files",
                    "description": "File access",
                    "category": "Documents",
                    "user_toggleable": True,
                },
                {
                    "id": "assistant-identity",
                    "name": "Assistant Identity",
                    "description": "Assistant identity controls",
                    "category": "System",
                    "user_toggleable": False,
                },
            ]
        ),
    )
    settings_record = SimpleNamespace(enabled_skills=["fs"])

    resolved = SettingsService._resolve_enabled_skills(settings_record)
    assert resolved == ["fs", "assistant-identity"]


def test_clean_updates_accepts_ai_provider_fields() -> None:
    cleaned = SettingsService.clean_updates(
        {
            "ai_primary_provider": "  OPENAI  ",
            "ai_fallback_to_managed": False,
        }
    )
    assert cleaned["ai_primary_provider"] == "openai"
    assert cleaned["ai_fallback_to_managed"] is False


def test_clean_updates_rejects_invalid_ai_provider() -> None:
    with pytest.raises(HTTPException) as exc_info:
        SettingsService.clean_updates({"ai_primary_provider": "unknown-provider"})
    assert exc_info.value.status_code == 400
    assert "Invalid ai_primary_provider" in str(exc_info.value.detail)


def test_build_response_defaults_ai_provider_policy() -> None:
    payload = SettingsService.build_response(settings_record=None, user_id="user-1")
    assert payload["ai_primary_provider"] is None
    assert payload["ai_fallback_to_managed"] is True
