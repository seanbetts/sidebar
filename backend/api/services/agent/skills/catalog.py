"""Skill catalog loader for UI and defaults."""

from __future__ import annotations

from datetime import date, datetime
from pathlib import Path
from typing import Any

import yaml

from api.services.tools.skill_metadata import (
    CATALOG_VERSION,
    EXPOSED_SKILLS,
    SKILL_DISPLAY,
    canonicalize_skill_id,
    get_credential_requirements,
    get_legacy_skill_ids,
    get_provider_dependency,
    get_skill_tier,
    is_skill_default_enabled,
    is_skill_installable,
    is_skill_user_toggleable,
)


class SkillCatalogService:
    """Load skill metadata from SKILL.md frontmatter."""

    _DEVELOPER_REQUIREMENT_MARKERS: tuple[str, ...] = (
        "ffmpeg",
        "installed via",
        "system package",
        "python package",
        "runtime",
        "doppler",
        "environment variable",
        "pyproject",
    )

    @staticmethod
    def catalog_version() -> int:
        """Return the current catalog version."""
        return CATALOG_VERSION

    @staticmethod
    def list_skills(skills_dir: Path) -> list[dict[str, Any]]:
        """List available skills with display metadata.

        Args:
            skills_dir: Root directory containing skills.

        Returns:
            List of skill metadata dicts.
        """
        skills: list[dict[str, Any]] = []
        seen_ids: set[str] = set()
        category_map = SkillCatalogService._category_map()

        if skills_dir.exists():
            for skill_path in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
                skill_md = skill_path / "SKILL.md"
                if not skill_md.exists():
                    continue

                metadata = SkillCatalogService._read_frontmatter(skill_md)
                canonical_id = canonicalize_skill_id(skill_path.name)
                if canonical_id in seen_ids:
                    continue

                skills.append(
                    SkillCatalogService._build_skill_entry(
                        skill_id=canonical_id,
                        metadata=metadata,
                        category=category_map.get(canonical_id, "Other"),
                    )
                )
                seen_ids.add(canonical_id)

        for fallback_id in ("ui-theme", "web-search", "memory"):
            if fallback_id not in seen_ids:
                skills.append(
                    SkillCatalogService._build_skill_entry(
                        skill_id=fallback_id,
                        metadata={},
                        category=category_map.get(fallback_id, "System"),
                    )
                )
                seen_ids.add(fallback_id)

        return [skill for skill in skills if str(skill["id"]) in EXPOSED_SKILLS]

    @staticmethod
    def _build_skill_entry(
        *,
        skill_id: str,
        metadata: dict[str, Any],
        category: str,
    ) -> dict[str, Any]:
        """Build one normalized catalog entry."""
        display = SkillCatalogService._display_metadata(skill_id)
        frontmatter_metadata = SkillCatalogService._nested_metadata(metadata)
        user_toggleable = is_skill_user_toggleable(skill_id)

        long_description = SkillCatalogService._coalesce_str(
            frontmatter_metadata.get("long_description"),
        )
        how_it_works = SkillCatalogService._coalesce_str(
            frontmatter_metadata.get("how_it_works"),
        )
        raw_requirements = SkillCatalogService._coalesce_str_list(
            frontmatter_metadata.get("requirements"),
        )
        credential_requirements = get_credential_requirements(skill_id)
        requirements = SkillCatalogService._normalize_user_requirements(
            raw_requirements,
            credential_requirements,
        )
        version = SkillCatalogService._coalesce_str(
            frontmatter_metadata.get("version"),
        )
        updated_at = SkillCatalogService._coalesce_str(
            frontmatter_metadata.get("updated_at"),
        )

        return {
            "id": skill_id,
            "legacy_ids": get_legacy_skill_ids(skill_id),
            "name": (
                SkillCatalogService._display_str(display, "name")
                or metadata.get("name")
                or skill_id
            ).strip(),
            "description": (
                SkillCatalogService._display_str(display, "description")
                or metadata.get("description")
                or ""
            ).strip(),
            "category": category,
            "icon_key": skill_id,
            "tier": get_skill_tier(skill_id),
            "provider_dependency": get_provider_dependency(skill_id),
            "credential_requirements": credential_requirements,
            "user_toggleable": user_toggleable,
            "default_enabled": is_skill_default_enabled(skill_id),
            "installable": is_skill_installable(skill_id),
            "status": "active",
            "show_required_badge": SkillCatalogService._display_bool(
                display,
                "show_required_badge",
                not user_toggleable,
            ),
            "long_description": long_description,
            "how_it_works": how_it_works,
            "requirements": requirements,
            "version": version,
            "updated_at": updated_at,
            # Reserved for future engagement features.
            "install_count": None,
            "upvotes": None,
            "downvotes": None,
            "current_user_vote": None,
        }

    @staticmethod
    def _read_frontmatter(skill_md: Path) -> dict[str, Any]:
        """Read YAML frontmatter from a SKILL.md file.

        Args:
            skill_md: Path to SKILL.md.

        Returns:
            Parsed frontmatter dict or empty dict.
        """
        text = skill_md.read_text(encoding="utf-8")
        if not text.startswith("---"):
            return {}

        parts = text.split("---", 2)
        if len(parts) < 3:
            return {}

        try:
            data = yaml.safe_load(parts[1]) or {}
        except yaml.YAMLError:
            return {}

        if not isinstance(data, dict):
            return {}

        return data

    @staticmethod
    def _nested_metadata(metadata: dict[str, Any]) -> dict[str, Any]:
        raw = metadata.get("metadata")
        if isinstance(raw, dict):
            return raw
        return {}

    @staticmethod
    def _display_metadata(skill_id: str) -> dict[str, Any]:
        raw = SKILL_DISPLAY.get(skill_id)
        if isinstance(raw, dict):
            return raw
        return {}

    @staticmethod
    def _display_str(display: dict[str, Any], key: str) -> str | None:
        value = display.get(key)
        if isinstance(value, str):
            return value
        return None

    @staticmethod
    def _display_bool(display: dict[str, Any], key: str, default: bool) -> bool:
        value = display.get(key)
        if isinstance(value, bool):
            return value
        return default

    @staticmethod
    def _coalesce_str(*values: Any) -> str | None:
        for value in values:
            if isinstance(value, str):
                normalized = value.strip()
                if normalized:
                    return normalized
            if isinstance(value, date | datetime):
                return value.isoformat()
        return None

    @staticmethod
    def _coalesce_str_list(*values: Any) -> list[str]:
        for value in values:
            if not isinstance(value, list):
                continue
            normalized = [
                item.strip() for item in value if isinstance(item, str) and item.strip()
            ]
            if normalized:
                return normalized
        return []

    @staticmethod
    def _normalize_user_requirements(
        requirements: list[str],
        credential_requirements: list[dict[str, Any]],
    ) -> list[str]:
        providers: set[str] = set()
        for credential_requirement in credential_requirements:
            provider = credential_requirement.get("provider")
            if not isinstance(provider, str):
                continue
            normalized_provider = provider.strip().lower()
            if normalized_provider:
                providers.add(normalized_provider)

        seen: set[str] = set()
        normalized_requirements: list[str] = []
        for requirement_text in requirements:
            normalized_requirement = requirement_text.strip().lower()
            if not normalized_requirement:
                continue
            if any(
                marker in normalized_requirement
                for marker in SkillCatalogService._DEVELOPER_REQUIREMENT_MARKERS
            ):
                continue
            if SkillCatalogService._is_credential_requirement_line(
                normalized_requirement,
                providers,
            ):
                continue
            if normalized_requirement in seen:
                continue
            seen.add(normalized_requirement)
            normalized_requirements.append(requirement_text.strip())

        return normalized_requirements

    @staticmethod
    def _is_credential_requirement_line(
        normalized_requirement: str,
        providers: set[str],
    ) -> bool:
        if not providers:
            return False
        if "api key" in normalized_requirement:
            return True
        if "key" not in normalized_requirement:
            return False
        return any(provider in normalized_requirement for provider in providers)

    @staticmethod
    def _category_map() -> dict[str, str]:
        """Return the static skill category map."""
        return {
            "files": "Documents",
            "notes": "Productivity",
            "tasks": "Productivity",
            "docx": "Documents",
            "pdf": "Documents",
            "pptx": "Documents",
            "xlsx": "Documents",
            "subdomain-discover": "Web",
            "web-crawler-policy": "Web",
            "web-save": "Web",
            "web-search": "Web",
            "memory": "System",
            "assistant-identity": "System",
            "assistant-soul": "System",
            "settings-profile-user": "System",
            "settings-other-preferences": "System",
            "product-feedback": "Development",
            "audio-transcribe": "Media",
            "youtube-download": "Media",
            "youtube-transcribe": "Media",
            "skill-creator": "Development",
            "ui-theme": "System",
            "prompt-preview": "System",
        }
