"""Provider key orchestration for user settings responses and BYOK endpoints."""

from __future__ import annotations

from typing import Any, Literal, cast

from fastapi import HTTPException

from api.config import settings
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.ai.registry import VALID_AI_PROVIDERS, AIProvider
from api.services.capabilities.runtime_state import RuntimeCapabilityService
from api.services.settings_service import SettingsService
from api.services.tools.skill_metadata import canonicalize_skill_id
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.user_settings_service import UserSettingsService


class UserAIProviderSettingsService:
    """Service methods for provider-key status and CRUD payloads."""

    @staticmethod
    def _normalize_provider(value: Any) -> AIProvider | None:
        """Return a canonical provider value when valid."""
        if not isinstance(value, str):
            return None
        candidate = value.strip().lower()
        if candidate in VALID_AI_PROVIDERS:
            return cast(AIProvider, candidate)
        return None

    @staticmethod
    def _resolve_primary_provider(db, user_id: str) -> AIProvider | None:
        """Return the user's selected primary provider when configured."""
        settings_record = UserSettingsService.get_settings(db, user_id)
        return UserAIProviderSettingsService._normalize_provider(
            getattr(settings_record, "ai_primary_provider", None)
            if settings_record
            else None
        )

    @staticmethod
    def _skill_requires_provider(
        skill_entry: dict[str, Any],
        provider: AIProvider,
    ) -> bool:
        """Return True when a skill requires the provider as a required API key."""
        requirements = skill_entry.get("credential_requirements")
        if not isinstance(requirements, list):
            return False

        for requirement in requirements:
            if not isinstance(requirement, dict):
                continue
            if not bool(requirement.get("required", False)):
                continue
            key_kind = str(requirement.get("key_kind", "api_key")).strip().lower()
            if key_kind != "api_key":
                continue
            requirement_provider = UserAIProviderSettingsService._normalize_provider(
                requirement.get("provider")
            )
            if requirement_provider == provider:
                return True
        return False

    @staticmethod
    def _enabled_store_skill_consumers(
        provider: AIProvider,
        *,
        enabled_skills: list[str],
        installed_store_skills: list[str],
        catalog_by_id: dict[str, dict[str, Any]],
    ) -> list[str]:
        """Return enabled installed Store skill IDs that consume this provider."""
        installed_store_set = set(installed_store_skills)
        consumers: list[str] = []
        for skill_id in enabled_skills:
            if skill_id not in installed_store_set:
                continue
            entry = catalog_by_id.get(skill_id)
            if not entry:
                continue
            if str(entry.get("tier", "")) != "store":
                continue
            if UserAIProviderSettingsService._skill_requires_provider(entry, provider):
                consumers.append(skill_id)
        return consumers

    @staticmethod
    def attach_primary_provider_key_status(
        db,
        *,
        user_id: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        """Attach selected primary provider key status fields to payload."""
        provider = UserAIProviderSettingsService._normalize_provider(
            payload.get("ai_primary_provider")
        )
        if provider is None:
            payload["ai_primary_provider_has_key"] = False
            payload["ai_primary_provider_key_last4"] = None
            return payload

        record = UserAIProviderKeyService.get_active_record(db, user_id, provider)
        payload["ai_primary_provider_has_key"] = record is not None
        payload["ai_primary_provider_key_last4"] = record.key_last4 if record else None
        return payload

    @staticmethod
    def get_provider_key_status(
        db,
        user_id: str,
        *,
        provider: str | None = None,
    ) -> dict[str, Any]:
        """Return BYOK status for a provider or the selected primary provider."""
        selected_provider = (
            UserAIProviderSettingsService._resolve_primary_provider(db, user_id)
            if provider is None
            else UserAIProviderSettingsService._normalize_provider(provider)
        )
        if provider is not None and selected_provider is None:
            raise HTTPException(status_code=400, detail="provider required")
        if selected_provider is None:
            return {"provider": None, "has_key": False, "key_last4": None}

        record = UserAIProviderKeyService.get_active_record(
            db,
            user_id,
            selected_provider,
        )
        return {
            "provider": selected_provider,
            "has_key": record is not None,
            "key_last4": record.key_last4 if record else None,
        }

    @staticmethod
    def upsert_provider_key(
        db,
        user_id: str,
        *,
        provider: str,
        api_key: str,
    ) -> dict[str, Any]:
        """Create or update a BYOK provider key."""
        selected_provider = UserAIProviderSettingsService._normalize_provider(provider)
        if selected_provider is None:
            raise HTTPException(status_code=400, detail="provider required")

        normalized_key = api_key.strip()
        if not normalized_key:
            raise HTTPException(status_code=400, detail="api_key required")

        record = UserAIProviderKeyService.upsert_key(
            db,
            user_id=user_id,
            provider=selected_provider,
            api_key=normalized_key,
        )
        return {
            "provider": selected_provider,
            "has_key": True,
            "key_last4": record.key_last4,
        }

    @staticmethod
    def disconnect_provider_consumer(
        db,
        user_id: str,
        *,
        provider: str,
        source: Literal["skill", "ai_provider"],
        skill_id: str | None = None,
    ) -> dict[str, Any]:
        """Disconnect a provider consumer and optionally delete key when unneeded."""
        selected_provider = UserAIProviderSettingsService._normalize_provider(provider)
        if selected_provider is None:
            raise HTTPException(status_code=400, detail="provider required")
        if source not in {"skill", "ai_provider"}:
            raise HTTPException(status_code=400, detail="source required")

        catalog = SkillCatalogService.list_skills(settings.skills_dir)
        catalog_by_id: dict[str, dict[str, Any]] = {
            str(item["id"]): item for item in catalog
        }

        settings_record = UserSettingsService.get_settings(db, user_id)
        enabled_skills = RuntimeCapabilityService.enabled_skill_ids(
            db,
            user_id=user_id,
            settings_record=settings_record,
        )
        installed_store_skills = RuntimeCapabilityService.installed_store_skill_ids(
            db,
            user_id=user_id,
            settings_record=settings_record,
        )
        ai_primary_provider = UserAIProviderSettingsService._normalize_provider(
            getattr(settings_record, "ai_primary_provider", None)
            if settings_record
            else None
        )

        original_enabled_skills = list(enabled_skills)
        original_ai_primary_provider = ai_primary_provider

        disabled_skill_ids: list[str] = []
        detached_ai_provider = False

        if source == "skill":
            normalized_skill_id = (skill_id or "").strip()
            if not normalized_skill_id:
                raise HTTPException(status_code=400, detail="skill_id required")
            canonical_skill_id = canonicalize_skill_id(normalized_skill_id)
            skill_entry = catalog_by_id.get(canonical_skill_id)
            if (
                not skill_entry
                or str(skill_entry.get("tier", "")) != "store"
                or not bool(skill_entry.get("installable", False))
            ):
                raise HTTPException(status_code=400, detail="Invalid skill ID")
            if canonical_skill_id not in installed_store_skills:
                raise HTTPException(status_code=400, detail="Invalid skill ID")
            if not UserAIProviderSettingsService._skill_requires_provider(
                skill_entry,
                selected_provider,
            ):
                raise HTTPException(
                    status_code=400,
                    detail="Skill does not require provider",
                )
            if not bool(skill_entry.get("user_toggleable", True)):
                raise HTTPException(status_code=409, detail="Skill cannot be disabled")

            if canonical_skill_id in enabled_skills:
                enabled_skills = [
                    item for item in enabled_skills if item != canonical_skill_id
                ]
                disabled_skill_ids = [canonical_skill_id]
        elif ai_primary_provider == selected_provider:
            ai_primary_provider = None
            detached_ai_provider = True

        remaining_skill_ids = (
            UserAIProviderSettingsService._enabled_store_skill_consumers(
                selected_provider,
                enabled_skills=enabled_skills,
                installed_store_skills=installed_store_skills,
                catalog_by_id=catalog_by_id,
            )
        )
        ai_provider_consumer = ai_primary_provider == selected_provider
        should_delete_provider_key = (
            not ai_provider_consumer and not remaining_skill_ids
        )

        should_update_enabled_skills = enabled_skills != original_enabled_skills
        should_update_ai_provider = ai_primary_provider != original_ai_primary_provider
        has_settings_updates = should_update_enabled_skills or should_update_ai_provider
        if has_settings_updates:
            UserSettingsService.upsert_settings(
                db,
                user_id,
                enabled_skills=(
                    SettingsService._normalize_enabled_skills(
                        enabled_skills,
                        catalog=catalog,
                    )
                    if should_update_enabled_skills
                    else UserSettingsService.UNSET
                ),
                ai_primary_provider=(
                    ai_primary_provider
                    if should_update_ai_provider
                    else UserSettingsService.UNSET
                ),
                commit=False,
            )

        deleted_provider_key = False
        if should_delete_provider_key:
            deleted_provider_key = UserAIProviderKeyService.soft_delete_key(
                db,
                user_id,
                selected_provider,
                commit=False,
            )

        if has_settings_updates or should_delete_provider_key:
            db.commit()

        current_settings = UserSettingsService.get_settings(db, user_id)
        response_settings = SettingsService.build_response(
            current_settings,
            user_id,
            db=db,
        )

        return {
            "provider": selected_provider,
            "source": source,
            "actions": {
                "disabled_skill_ids": disabled_skill_ids,
                "detached_ai_provider": detached_ai_provider,
                "deleted_provider_key": deleted_provider_key,
            },
            "remaining_consumers": {
                "ai_provider": ai_provider_consumer,
                "skill_ids": remaining_skill_ids,
            },
            "settings": {
                "enabled_skills": response_settings["enabled_skills"],
                "installed_store_skills": response_settings["installed_store_skills"],
                "ai_primary_provider": response_settings["ai_primary_provider"],
            },
        }

    @staticmethod
    def delete_provider_key(
        db,
        user_id: str,
        *,
        provider: str | None = None,
    ) -> dict[str, Any]:
        """Soft delete a BYOK provider key."""
        selected_provider = (
            UserAIProviderSettingsService._resolve_primary_provider(db, user_id)
            if provider is None
            else UserAIProviderSettingsService._normalize_provider(provider)
        )
        if provider is not None and selected_provider is None:
            raise HTTPException(status_code=400, detail="provider required")
        if selected_provider is None:
            return {"provider": None, "has_key": False, "key_last4": None}

        UserAIProviderKeyService.soft_delete_key(db, user_id, selected_provider)
        return {"provider": selected_provider, "has_key": False, "key_last4": None}
