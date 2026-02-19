"""Skill catalog loader for UI and defaults."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from api.services.tools.skill_metadata import (
    EXPOSED_SKILLS,
    SKILL_DISPLAY,
    is_skill_user_toggleable,
)


class SkillCatalogService:
    """Load skill metadata from SKILL.md frontmatter."""

    @staticmethod
    def list_skills(skills_dir: Path) -> list[dict[str, str | bool]]:
        """List available skills with display metadata.

        Args:
            skills_dir: Root directory containing skills.

        Returns:
            List of skill metadata dicts.
        """
        skills: list[dict[str, str | bool]] = []
        category_map = SkillCatalogService._category_map()

        if not skills_dir.exists():
            return skills

        for skill_path in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
            skill_md = skill_path / "SKILL.md"
            if not skill_md.exists():
                continue

            metadata = SkillCatalogService._read_frontmatter(skill_md)
            skill_id = skill_path.name
            display = SkillCatalogService._display_metadata(skill_id)
            name = (
                SkillCatalogService._display_str(display, "name")
                or metadata.get("name")
                or skill_id
            ).strip()
            description = (
                SkillCatalogService._display_str(display, "description")
                or metadata.get("description")
                or ""
            ).strip()
            category = category_map.get(skill_id, "Other")
            user_toggleable = is_skill_user_toggleable(skill_id)
            skills.append(
                {
                    "id": skill_id,
                    "name": name,
                    "description": description,
                    "category": category,
                    "user_toggleable": user_toggleable,
                    "show_required_badge": SkillCatalogService._display_bool(
                        display,
                        "show_required_badge",
                        not user_toggleable,
                    ),
                }
            )

        if "ui-theme" not in {str(skill["id"]) for skill in skills}:
            ui_display = SkillCatalogService._display_metadata("ui-theme")
            skills.append(
                {
                    "id": "ui-theme",
                    "name": SkillCatalogService._display_str(ui_display, "name")
                    or "UI Theme",
                    "description": SkillCatalogService._display_str(
                        ui_display, "description"
                    )
                    or "Allow the assistant to switch light or dark mode.",
                    "category": category_map.get("ui-theme", "System"),
                    "user_toggleable": is_skill_user_toggleable("ui-theme"),
                    "show_required_badge": SkillCatalogService._display_bool(
                        ui_display,
                        "show_required_badge",
                        False,
                    ),
                }
            )

        if "web-search" not in {str(skill["id"]) for skill in skills}:
            web_display = SkillCatalogService._display_metadata("web-search")
            skills.append(
                {
                    "id": "web-search",
                    "name": SkillCatalogService._display_str(web_display, "name")
                    or "Web Search",
                    "description": SkillCatalogService._display_str(
                        web_display, "description"
                    )
                    or "Search the live web for up-to-date information.",
                    "category": category_map.get("web-search", "Web"),
                    "user_toggleable": is_skill_user_toggleable("web-search"),
                    "show_required_badge": SkillCatalogService._display_bool(
                        web_display,
                        "show_required_badge",
                        False,
                    ),
                }
            )

        if "memory" not in {str(skill["id"]) for skill in skills}:
            memory_display = SkillCatalogService._display_metadata("memory")
            skills.append(
                {
                    "id": "memory",
                    "name": SkillCatalogService._display_str(memory_display, "name")
                    or "Memory",
                    "description": SkillCatalogService._display_str(
                        memory_display, "description"
                    )
                    or "Store and manage persistent user memories.",
                    "category": category_map.get("memory", "System"),
                    "user_toggleable": is_skill_user_toggleable("memory"),
                    "show_required_badge": SkillCatalogService._display_bool(
                        memory_display,
                        "show_required_badge",
                        False,
                    ),
                }
            )

        return [skill for skill in skills if str(skill["id"]) in EXPOSED_SKILLS]

    @staticmethod
    def _read_frontmatter(skill_md: Path) -> dict[str, str]:
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
    def _category_map() -> dict[str, str]:
        """Return the static skill category map."""
        return {
            "fs": "Documents",
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
            "audio-transcribe": "Media",
            "youtube-download": "Media",
            "youtube-transcribe": "Media",
            "skill-creator": "Development",
            "ui-theme": "System",
            "prompt-preview": "System",
        }
