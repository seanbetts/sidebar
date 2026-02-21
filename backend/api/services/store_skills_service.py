"""Service layer for Store skills install state."""

from __future__ import annotations

from typing import Any, cast

from sqlalchemy.orm import Session

from api.config import settings
from api.exceptions import BadRequestError
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.ai.registry import VALID_AI_PROVIDERS, AIProvider
from api.services.settings_service import SettingsService
from api.services.tools.skill_metadata import canonicalize_skill_id
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.user_settings_service import UserSettingsService


class StoreSkillsService:
    """Manage install state for Store-tier skills."""

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
    def _required_provider_requirements(
        skill_entry: dict[str, Any],
    ) -> list[AIProvider]:
        """Return required provider dependencies for a skill install."""
        requirements = skill_entry.get("credential_requirements")
        if not isinstance(requirements, list):
            return []

        required: list[AIProvider] = []
        seen: set[AIProvider] = set()
        for requirement in requirements:
            if not isinstance(requirement, dict):
                continue
            if not bool(requirement.get("required", False)):
                continue
            key_kind = str(requirement.get("key_kind", "api_key")).strip().lower()
            if key_kind != "api_key":
                raise BadRequestError("Invalid skill credential requirements")
            provider = StoreSkillsService._normalize_provider(
                requirement.get("provider")
            )
            if provider is None:
                raise BadRequestError("Invalid skill credential requirements")
            if provider in seen:
                continue
            required.append(provider)
            seen.add(provider)
        return required

    @staticmethod
    def _normalize_install_provider_keys(
        provider_keys: list[dict[str, Any]],
    ) -> dict[AIProvider, str]:
        """Validate install-time provider keys and normalize by provider."""
        normalized: dict[AIProvider, str] = {}
        for raw in provider_keys:
            provider = StoreSkillsService._normalize_provider(raw.get("provider"))
            if provider is None:
                raise BadRequestError("provider required")
            api_key = raw.get("api_key")
            if not isinstance(api_key, str) or not api_key.strip():
                raise BadRequestError("api_key required")
            if provider in normalized:
                raise BadRequestError(
                    "Duplicate provider key for install request",
                    details={
                        "error_type": "SKILL_CREDENTIAL_DUPLICATE_PROVIDER",
                        "provider": provider,
                    },
                )
            normalized[provider] = api_key.strip()
        return normalized

    @staticmethod
    def _ensure_install_credentials(
        db: Session,
        *,
        user_id: str,
        skill_id: str,
        skill_entry: dict[str, Any],
        provider_keys: list[dict[str, Any]],
    ) -> None:
        """Ensure required install credentials exist or are provided in request."""
        required_providers = StoreSkillsService._required_provider_requirements(
            skill_entry
        )
        provided_by_provider = StoreSkillsService._normalize_install_provider_keys(
            provider_keys
        )
        missing_requirements: list[dict[str, str | bool]] = []

        for provider in required_providers:
            provided_api_key = provided_by_provider.pop(provider, None)
            if provided_api_key is not None:
                try:
                    UserAIProviderKeyService.upsert_key(
                        db,
                        user_id=user_id,
                        provider=provider,
                        api_key=provided_api_key,
                        commit=False,
                    )
                except ValueError as exc:
                    raise BadRequestError(
                        "Invalid provider API key",
                        details={
                            "error_type": "SKILL_CREDENTIAL_INVALID",
                            "skill_id": skill_id,
                            "provider": provider,
                        },
                    ) from exc
                continue

            if UserAIProviderKeyService.has_active_key(db, user_id, provider):
                continue
            missing_requirements.append(
                {
                    "provider": provider,
                    "key_kind": "api_key",
                    "required": True,
                }
            )

        if provided_by_provider:
            unexpected = sorted(provided_by_provider.keys())
            raise BadRequestError(
                "Unexpected provider key for skill install",
                details={
                    "error_type": "SKILL_CREDENTIAL_UNEXPECTED_PROVIDER",
                    "skill_id": skill_id,
                    "required_providers": required_providers,
                    "unexpected_providers": unexpected,
                },
            )

        if missing_requirements:
            raise BadRequestError(
                "Skill install requires provider API key",
                details={
                    "error_type": "SKILL_CREDENTIAL_REQUIRED",
                    "skill_id": skill_id,
                    "required_providers": required_providers,
                    "missing_requirements": missing_requirements,
                },
            )

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
        provider_keys: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """Install a Store skill and auto-enable it in one transaction."""
        normalized_input = (skill_id or "").strip()
        canonical_id = canonicalize_skill_id(normalized_input)
        normalized_provider_keys = provider_keys or []
        catalog = SkillCatalogService.list_skills(settings.skills_dir)
        catalog_by_id = {str(skill["id"]): skill for skill in catalog}
        skill_entry = catalog_by_id.get(canonical_id)

        if not skill_entry:
            raise BadRequestError("Invalid skill ID")
        if str(skill_entry.get("tier", "")) != "store" or not bool(
            skill_entry.get("installable", False)
        ):
            raise BadRequestError("Skill is not installable from Store skills")
        StoreSkillsService._ensure_install_credentials(
            db,
            user_id=user_id,
            skill_id=canonical_id,
            skill_entry=skill_entry,
            provider_keys=normalized_provider_keys,
        )

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

    @staticmethod
    def uninstall_store_skill(
        db: Session,
        *,
        user_id: str,
        skill_id: str,
    ) -> dict[str, Any]:
        """Uninstall a Store skill and disable it in one transaction."""
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

        filtered_enabled_skills = [
            skill for skill in enabled_skills if skill != canonical_id
        ]
        filtered_installed_store_skills = [
            skill for skill in installed_store_skills if skill != canonical_id
        ]

        normalized_enabled_skills = SettingsService._normalize_enabled_skills(
            filtered_enabled_skills,
            catalog=catalog,
        )
        normalized_installed_store_skills = (
            StoreSkillsService._normalize_installed_store_skills(
                filtered_installed_store_skills,
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
