"""Service layer for Store skills install state."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from api.config import settings
from api.exceptions import BadRequestError
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.settings_service import SettingsService
from api.services.tools.skill_metadata import canonicalize_skill_id
from api.services.user_settings_service import UserSettingsService


class StoreSkillsService:
    """Manage install state for Store-tier skills."""

    @staticmethod
    def _normalize_installed_store_skills(
        skill_ids: list[str],
        *,
        catalog: list[dict[str, Any]],
    ) -> list[str]:
        """Normalize installed store skills against catalog metadata."""
        allowed_store_ids = {
            str(skill["id"])
            for skill in catalog
            if str(skill.get("tier", "")) == "store"
        }
        normalized: list[str] = []
        seen: set[str] = set()
        for skill_id in skill_ids:
            canonical_id = canonicalize_skill_id(skill_id)
            if canonical_id in allowed_store_ids and canonical_id not in seen:
                normalized.append(canonical_id)
                seen.add(canonical_id)
        return normalized

    @staticmethod
    def install_store_skill(
        db: Session,
        *,
        user_id: str,
        skill_id: str,
    ) -> dict[str, Any]:
        """Install a Store skill and auto-enable it in one transaction."""
        normalized_input = (skill_id or "").strip()
        canonical_id = canonicalize_skill_id(normalized_input)
        catalog = SkillCatalogService.list_skills(settings.skills_dir)
        catalog_by_id = {str(skill["id"]): skill for skill in catalog}
        skill_entry = catalog_by_id.get(canonical_id)

        if not skill_entry:
            raise BadRequestError("Invalid skill ID")
        if str(skill_entry.get("tier", "")) != "store" or not bool(
            skill_entry.get("installable", False)
        ):
            raise BadRequestError("Skill is not installable from Store skills")

        current_settings = UserSettingsService.get_settings(db, user_id)
        enabled_skills = SettingsService.resolve_enabled_skills(current_settings)
        installed_store_skills = SettingsService._resolve_installed_store_skills(
            current_settings
        )

        if canonical_id not in installed_store_skills:
            installed_store_skills.append(canonical_id)
        if canonical_id not in enabled_skills:
            enabled_skills.append(canonical_id)

        normalized_enabled_skills = SettingsService._normalize_enabled_skills(
            enabled_skills,
            catalog=catalog,
        )
        normalized_installed_store_skills = (
            StoreSkillsService._normalize_installed_store_skills(
                installed_store_skills,
                catalog=catalog,
            )
        )

        updated_settings = UserSettingsService.upsert_settings(
            db,
            user_id,
            enabled_skills=normalized_enabled_skills,
            installed_store_skills=normalized_installed_store_skills,
        )
        payload = SettingsService.build_response(updated_settings, user_id)

        return {
            "skill_id": canonical_id,
            "installed": canonical_id in payload["installed_store_skills"],
            "enabled": canonical_id in payload["enabled_skills"],
            "enabled_skills": payload["enabled_skills"],
            "installed_store_skills": payload["installed_store_skills"],
        }
