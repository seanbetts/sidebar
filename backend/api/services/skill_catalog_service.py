"""Skill catalog loader for UI and defaults."""
from __future__ import annotations

from pathlib import Path
from typing import Dict, List

import yaml

from api.services.tools.skill_metadata import SKILL_DISPLAY, EXPOSED_SKILLS


class SkillCatalogService:
    """Load skill metadata from SKILL.md frontmatter."""

    @staticmethod
    def list_skills(skills_dir: Path) -> List[Dict[str, str]]:
        skills: List[Dict[str, str]] = []
        category_map = SkillCatalogService._category_map()

        if not skills_dir.exists():
            return skills

        for skill_path in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
            skill_md = skill_path / "SKILL.md"
            if not skill_md.exists():
                continue

            metadata = SkillCatalogService._read_frontmatter(skill_md)
            skill_id = skill_path.name
            display = SKILL_DISPLAY.get(skill_id, {})
            name = (display.get("name") or metadata.get("name") or skill_id).strip()
            description = (display.get("description") or metadata.get("description") or "").strip()
            category = category_map.get(skill_id, "Other")
            skills.append(
                {
                    "id": skill_id,
                    "name": name,
                    "description": description,
                    "category": category,
                }
            )

        if "ui-theme" not in {skill["id"] for skill in skills}:
            ui_display = SKILL_DISPLAY.get("ui-theme", {})
            skills.append(
                {
                    "id": "ui-theme",
                    "name": ui_display.get("name", "UI Theme"),
                    "description": ui_display.get(
                        "description",
                        "Allow the assistant to switch light or dark mode.",
                    ),
                    "category": category_map.get("ui-theme", "System"),
                }
            )

        if "web-search" not in {skill["id"] for skill in skills}:
            web_display = SKILL_DISPLAY.get("web-search", {})
            skills.append(
                {
                    "id": "web-search",
                    "name": web_display.get("name", "Web Search"),
                    "description": web_display.get(
                        "description",
                        "Search the live web for up-to-date information.",
                    ),
                    "category": category_map.get("web-search", "Web"),
                }
            )

        if "memory" not in {skill["id"] for skill in skills}:
            memory_display = SKILL_DISPLAY.get("memory", {})
            skills.append(
                {
                    "id": "memory",
                    "name": memory_display.get("name", "Memory"),
                    "description": memory_display.get(
                        "description",
                        "Store and manage persistent user memories.",
                    ),
                    "category": category_map.get("memory", "System"),
                }
            )

        return [skill for skill in skills if skill["id"] in EXPOSED_SKILLS]

    @staticmethod
    def _read_frontmatter(skill_md: Path) -> Dict[str, str]:
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
    def _category_map() -> Dict[str, str]:
        return {
            "fs": "Documents",
            "notes": "Documents",
            "docx": "Documents",
            "pdf": "Documents",
            "pptx": "Documents",
            "xlsx": "Documents",
            "subdomain-discover": "Web",
            "web-crawler-policy": "Web",
            "web-save": "Web",
            "web-search": "Web",
            "memory": "System",
            "audio-transcribe": "Media",
            "youtube-download": "Media",
            "youtube-transcribe": "Media",
            "mcp-builder": "Development",
            "skill-creator": "Development",
            "ui-theme": "System",
            "prompt-preview": "System",
        }
