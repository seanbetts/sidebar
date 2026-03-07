"""Service helpers for normalized per-user skill state."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.config import settings
from api.models.user_skill_state import UserSkillState
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.tools.skill_metadata import canonicalize_skill_id


class SkillStateService:
    """Manage normalized user skill state rows."""

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

    @staticmethod
    def _default_enabled_skill_ids(catalog: list[dict[str, Any]]) -> list[str]:
        return [
            str(skill["id"]) for skill in catalog if bool(skill.get("default_enabled"))
        ]

    @staticmethod
    def _normalize_requested_skill_ids(
        raw_skill_ids: list[str] | None,
        *,
        allowed_skill_ids: set[str],
    ) -> list[str]:
        normalized: list[str] = []
        seen: set[str] = set()
        for raw_skill_id in raw_skill_ids or []:
            canonical_id = canonicalize_skill_id(str(raw_skill_id).strip())
            if canonical_id in allowed_skill_ids and canonical_id not in seen:
                normalized.append(canonical_id)
                seen.add(canonical_id)
        return normalized

    @classmethod
    def _backfill_state_map(
        cls,
        *,
        settings_record: Any,
        catalog: list[dict[str, Any]],
    ) -> dict[str, dict[str, bool]]:
        allowed_skill_ids = {str(skill["id"]) for skill in catalog}
        required_skill_ids = cls._required_skill_ids(catalog)
        store_skill_ids = cls._store_skill_ids(catalog)

        installed_skill_ids = cls._normalize_requested_skill_ids(
            getattr(settings_record, "installed_store_skills", None),
            allowed_skill_ids=store_skill_ids,
        )
        enabled_raw = getattr(settings_record, "enabled_skills", None)
        if enabled_raw is None:
            enabled_skill_ids = cls._default_enabled_skill_ids(catalog)
            for skill_id in installed_skill_ids:
                if skill_id not in enabled_skill_ids:
                    enabled_skill_ids.append(skill_id)
        else:
            enabled_skill_ids = cls._normalize_requested_skill_ids(
                enabled_raw,
                allowed_skill_ids=allowed_skill_ids,
            )

        for skill_id in required_skill_ids:
            if skill_id not in enabled_skill_ids:
                enabled_skill_ids.append(skill_id)

        state_map: dict[str, dict[str, bool]] = {}
        for skill_id in enabled_skill_ids:
            state_map[skill_id] = {"enabled": True, "installed": False}
        for skill_id in installed_skill_ids:
            state_map.setdefault(skill_id, {"enabled": False, "installed": False})
            state_map[skill_id]["installed"] = True
        return state_map

    @staticmethod
    def list_active_skill_states(db: Session, user_id: str) -> list[UserSkillState]:
        """Return active skill-state rows for a user."""
        return (
            db.query(UserSkillState)
            .filter(
                UserSkillState.user_id == user_id,
                UserSkillState.deleted_at.is_(None),
            )
            .order_by(UserSkillState.created_at.asc(), UserSkillState.skill_id.asc())
            .all()
        )

    @staticmethod
    def upsert_skill_state(
        db: Session,
        *,
        user_id: str,
        skill_id: str,
        enabled: bool,
        installed: bool,
        metadata_: dict[str, Any] | None = None,
        commit: bool = True,
    ) -> UserSkillState:
        """Create or update one active skill-state row."""
        canonical_skill_id = canonicalize_skill_id(skill_id)
        now = datetime.now(UTC)
        state = (
            db.query(UserSkillState)
            .filter(
                UserSkillState.user_id == user_id,
                UserSkillState.skill_id == canonical_skill_id,
                UserSkillState.deleted_at.is_(None),
            )
            .first()
        )

        if state is None:
            state = UserSkillState(
                user_id=user_id,
                skill_id=canonical_skill_id,
                enabled=enabled,
                installed=installed,
                metadata_=dict(metadata_ or {}),
                created_at=now,
                updated_at=now,
            )
            db.add(state)
        else:
            state.enabled = enabled
            state.installed = installed
            if metadata_ is not None:
                state.metadata_ = dict(metadata_)
                flag_modified(state, "metadata_")
            state.updated_at = now

        db.flush()
        if commit:
            db.commit()
        return state

    @classmethod
    def backfill_from_user_settings(
        cls,
        db: Session,
        user_id: str,
        *,
        settings_record: Any | None = None,
        commit: bool = True,
    ) -> list[UserSkillState]:
        """Mirror legacy settings arrays into normalized skill-state rows."""
        if settings_record is None:
            from api.services.user_settings_service import UserSettingsService

            settings_record = UserSettingsService.get_settings(db, user_id)
        if settings_record is not None and not (
            hasattr(settings_record, "enabled_skills")
            or hasattr(settings_record, "installed_store_skills")
        ):
            return cls.list_active_skill_states(db, user_id)
        catalog = cls._catalog()
        state_map = cls._backfill_state_map(
            settings_record=settings_record, catalog=catalog
        )
        existing_states = {
            state.skill_id: state for state in cls.list_active_skill_states(db, user_id)
        }

        for skill_id, desired_state in state_map.items():
            existing_metadata = existing_states.get(skill_id)
            cls.upsert_skill_state(
                db,
                user_id=user_id,
                skill_id=skill_id,
                enabled=desired_state["enabled"],
                installed=desired_state["installed"],
                metadata_=(
                    dict(existing_metadata.metadata_) if existing_metadata else {}
                ),
                commit=False,
            )

        retained_skill_ids = set(state_map)
        for skill_id, existing_state in existing_states.items():
            if skill_id in retained_skill_ids:
                continue
            cls.upsert_skill_state(
                db,
                user_id=user_id,
                skill_id=skill_id,
                enabled=False,
                installed=False,
                metadata_=dict(existing_state.metadata_),
                commit=False,
            )

        if commit:
            db.commit()
        return cls.list_active_skill_states(db, user_id)

    @classmethod
    def replace_enabled_skill_selection(
        cls,
        db: Session,
        user_id: str,
        enabled_skill_ids: list[str],
        *,
        commit: bool = True,
    ) -> list[UserSkillState]:
        """Replace enabled selection while preserving required skills."""
        catalog = cls._catalog()
        allowed_skill_ids = {str(skill["id"]) for skill in catalog}
        required_skill_ids = cls._required_skill_ids(catalog)
        requested_skill_ids = cls._normalize_requested_skill_ids(
            enabled_skill_ids,
            allowed_skill_ids=allowed_skill_ids,
        )
        for skill_id in required_skill_ids:
            if skill_id not in requested_skill_ids:
                requested_skill_ids.append(skill_id)

        active_states = {
            state.skill_id: state for state in cls.list_active_skill_states(db, user_id)
        }
        target_skill_ids = set(requested_skill_ids) | set(active_states)
        for skill_id in target_skill_ids:
            existing_state = active_states.get(skill_id)
            cls.upsert_skill_state(
                db,
                user_id=user_id,
                skill_id=skill_id,
                enabled=skill_id in requested_skill_ids,
                installed=existing_state.installed if existing_state else False,
                metadata_=(dict(existing_state.metadata_) if existing_state else {}),
                commit=False,
            )

        if commit:
            db.commit()
        return cls.list_active_skill_states(db, user_id)

    @classmethod
    def set_skill_installed(
        cls,
        db: Session,
        *,
        user_id: str,
        skill_id: str,
        installed: bool,
        commit: bool = True,
    ) -> UserSkillState:
        """Set install state for one skill and keep enablement coherent."""
        active_state = (
            db.query(UserSkillState)
            .filter(
                UserSkillState.user_id == user_id,
                UserSkillState.skill_id == canonicalize_skill_id(skill_id),
                UserSkillState.deleted_at.is_(None),
            )
            .first()
        )
        next_enabled = active_state.enabled if active_state else False
        if not installed and active_state is None:
            next_enabled = False
        if not installed:
            next_enabled = False
        return cls.upsert_skill_state(
            db,
            user_id=user_id,
            skill_id=skill_id,
            enabled=next_enabled,
            installed=installed,
            metadata_=(dict(active_state.metadata_) if active_state else {}),
            commit=commit,
        )
