"""Runtime capability state derived from registry, user state, and availability."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from api.config import settings
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.capabilities.skill_state_service import SkillStateService
from api.services.capabilities.types import RuntimeCapabilityState
from api.services.external_connections.availability_service import (
    ExternalConnectionAvailabilityService,
)
from api.services.user_settings_service import UserSettingsService


class RuntimeCapabilityService:
    """Join static capability metadata with normalized per-user runtime state."""

    @staticmethod
    def _catalog() -> list[dict[str, Any]]:
        return SkillCatalogService.list_skills(settings.skills_dir)

    @staticmethod
    def _required_skill_ids(catalog: list[dict[str, Any]]) -> list[str]:
        return [
            str(skill["id"])
            for skill in catalog
            if bool(skill.get("user_toggleable", True)) is False
        ]

    @staticmethod
    def _store_skill_ids(catalog: list[dict[str, Any]]) -> set[str]:
        return {
            str(skill["id"])
            for skill in catalog
            if str(skill.get("tier", "standard")) == "store"
        }

    @classmethod
    def _normalized_state_map(
        cls,
        db: Session,
        *,
        user_id: str,
        settings_record: Any | None,
        catalog: list[dict[str, Any]],
    ) -> dict[str, dict[str, bool]]:
        active_states = SkillStateService.list_active_skill_states(db, user_id)
        if not active_states:
            if settings_record is None:
                settings_record = UserSettingsService.get_settings(db, user_id)
            return SkillStateService._backfill_state_map(
                settings_record=settings_record,
                catalog=catalog,
            )

        state_map = {
            state.skill_id: {
                "enabled": bool(state.enabled),
                "installed": bool(state.installed),
            }
            for state in active_states
        }
        for skill_id in cls._required_skill_ids(catalog):
            state_map.setdefault(skill_id, {"enabled": True, "installed": False})
            state_map[skill_id]["enabled"] = True
        return state_map

    @classmethod
    def list_runtime_states(
        cls,
        db: Session,
        *,
        user_id: str,
        settings_record: Any | None = None,
    ) -> list[RuntimeCapabilityState]:
        """Return ordered runtime capability states for the visible skill catalog."""
        catalog = cls._catalog()
        store_skill_ids = cls._store_skill_ids(catalog)
        state_map = cls._normalized_state_map(
            db,
            user_id=user_id,
            settings_record=settings_record,
            catalog=catalog,
        )

        runtime_states: list[RuntimeCapabilityState] = []
        for skill_entry in catalog:
            skill_id = str(skill_entry["id"])
            raw_state = state_map.get(skill_id, {"enabled": False, "installed": False})
            installed = bool(raw_state.get("installed", False))
            enabled = bool(raw_state.get("enabled", False))
            if skill_id in store_skill_ids and not installed:
                enabled = False
            (
                availability_status,
                availability_reason,
                availability_remediation,
            ) = ExternalConnectionAvailabilityService.resolve_skill_availability(
                db,
                user_id=user_id,
                skill_entry=skill_entry,
            )
            runtime_states.append(
                RuntimeCapabilityState(
                    skill_id=skill_id,
                    enabled=enabled,
                    installed=installed,
                    availability_status=availability_status,
                    availability_reason=availability_reason,
                    availability_remediation=availability_remediation,
                )
            )
        return runtime_states

    @classmethod
    def runtime_state_map(
        cls,
        db: Session,
        *,
        user_id: str,
        settings_record: Any | None = None,
    ) -> dict[str, RuntimeCapabilityState]:
        """Return runtime capability state keyed by skill ID."""
        return {
            state.skill_id: state
            for state in cls.list_runtime_states(
                db,
                user_id=user_id,
                settings_record=settings_record,
            )
        }

    @classmethod
    def enabled_skill_ids(
        cls,
        db: Session,
        *,
        user_id: str,
        settings_record: Any | None = None,
    ) -> list[str]:
        """Return enabled skill IDs in catalog order."""
        return [
            state.skill_id
            for state in cls.list_runtime_states(
                db,
                user_id=user_id,
                settings_record=settings_record,
            )
            if state.enabled
        ]

    @classmethod
    def installed_store_skill_ids(
        cls,
        db: Session,
        *,
        user_id: str,
        settings_record: Any | None = None,
    ) -> list[str]:
        """Return installed Store skill IDs in catalog order."""
        catalog_by_id = {str(skill["id"]): skill for skill in cls._catalog()}
        return [
            state.skill_id
            for state in cls.list_runtime_states(
                db,
                user_id=user_id,
                settings_record=settings_record,
            )
            if state.installed
            and str(catalog_by_id.get(state.skill_id, {}).get("tier", "")) == "store"
        ]
