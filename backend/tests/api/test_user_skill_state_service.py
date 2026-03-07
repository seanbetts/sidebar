from __future__ import annotations

from datetime import UTC, datetime
from importlib import import_module

import pytest

from api.services.agent.skills.catalog import SkillCatalogService
from api.services.user_settings_service import UserSettingsService


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


def _user_skill_state_model():
    try:
        module = import_module("api.models.user_skill_state")
    except ModuleNotFoundError:
        pytest.fail("UserSkillState model module missing: api.models.user_skill_state")
    model = getattr(module, "UserSkillState", None)
    if model is None:
        pytest.fail("UserSkillState model class missing")
    return model


def _catalog_fixture() -> list[dict[str, object]]:
    return [
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


def test_backfill_from_user_settings_creates_one_row_per_skill(
    test_db,
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(lambda _skills_dir: _catalog_fixture()),
    )
    user_id = "skill-state-backfill-user"
    UserSettingsService.upsert_settings(
        test_db,
        user_id,
        enabled_skills=["files", "audio-transcribe"],
        installed_store_skills=["audio-transcribe"],
    )

    service = _skill_state_service()
    service.backfill_from_user_settings(test_db, user_id)

    states = service.list_active_skill_states(test_db, user_id)
    by_skill = {state.skill_id: state for state in states}
    assert set(by_skill) == {"files", "assistant-identity", "audio-transcribe"}
    assert by_skill["files"].enabled is True
    assert by_skill["files"].installed is False
    assert by_skill["assistant-identity"].enabled is True
    assert by_skill["assistant-identity"].installed is False
    assert by_skill["audio-transcribe"].enabled is True
    assert by_skill["audio-transcribe"].installed is True


def test_replace_enabled_skill_selection_preserves_required_skills(
    test_db,
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        SkillCatalogService,
        "list_skills",
        staticmethod(lambda _skills_dir: _catalog_fixture()),
    )

    service = _skill_state_service()
    service.replace_enabled_skill_selection(test_db, "required-skill-user", ["files"])

    states = service.list_active_skill_states(test_db, "required-skill-user")
    by_skill = {state.skill_id: state for state in states}
    assert by_skill["files"].enabled is True
    assert by_skill["assistant-identity"].enabled is True


def test_upsert_skill_state_updates_existing_active_row_without_duplicates(
    test_db,
) -> None:
    service = _skill_state_service()
    model = _user_skill_state_model()
    user_id = "skill-state-upsert-user"

    service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="files",
        enabled=False,
        installed=False,
    )
    service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="files",
        enabled=True,
        installed=True,
        metadata_={"source": "backfill"},
    )

    active_rows = (
        test_db.query(model)
        .filter(
            model.user_id == user_id,
            model.skill_id == "files",
            model.deleted_at.is_(None),
        )
        .all()
    )
    assert len(active_rows) == 1
    assert active_rows[0].enabled is True
    assert active_rows[0].installed is True
    assert active_rows[0].metadata_ == {"source": "backfill"}


def test_upsert_skill_state_recreates_after_soft_delete_without_duplicate_active_rows(
    test_db,
) -> None:
    service = _skill_state_service()
    model = _user_skill_state_model()
    user_id = "skill-state-soft-delete-user"

    state = service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        enabled=True,
        installed=False,
    )
    state.deleted_at = datetime.now(UTC)
    test_db.commit()

    service.upsert_skill_state(
        test_db,
        user_id=user_id,
        skill_id="audio-transcribe",
        enabled=False,
        installed=True,
    )

    rows = (
        test_db.query(model)
        .filter(model.user_id == user_id, model.skill_id == "audio-transcribe")
        .order_by(model.created_at.asc())
        .all()
    )
    active_rows = [row for row in rows if row.deleted_at is None]
    assert len(rows) == 2
    assert len(active_rows) == 1
    assert active_rows[0].enabled is False
    assert active_rows[0].installed is True
