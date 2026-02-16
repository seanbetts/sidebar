from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from api.services.settings_service import (
    DEFAULT_ASSISTANT_IDENTITY,
    MAX_ASSISTANT_IDENTITY_NAME_CHARS,
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


def test_build_response_resolves_default_assistant_identity() -> None:
    payload = SettingsService.build_response(settings_record=None, user_id="user-1")
    assert payload["assistant_identity"] == DEFAULT_ASSISTANT_IDENTITY


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

    payload = SettingsService.build_response(settings_record=settings_record, user_id="user-1")
    assert payload["assistant_identity"]["name"] == "Navigator"
    assert payload["assistant_identity"]["tone"] == "Calm and technical."
    assert payload["assistant_identity"]["values"] == "Accuracy and focus."
    assert payload["assistant_identity"]["boundaries"] == "No fabricated claims."
