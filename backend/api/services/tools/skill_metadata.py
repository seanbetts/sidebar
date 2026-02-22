"""Skill metadata and catalog helpers for tool listings."""

from __future__ import annotations

from typing import Any, Literal

CATALOG_VERSION = 5

SkillTier = Literal["required", "standard", "store"]

SKILL_ID_ALIASES = {
    "fs": "files",
}

LEGACY_SKILL_IDS: dict[str, list[str]] = {
    "files": ["fs"],
}

SKILL_DISPLAY = {
    "files": {
        "name": "Files",
        "description": "Search, read, write, rename, pin and delete files",
    },
    "notes": {
        "name": "Notes",
        "description": (
            "Search, read, create, update, rename, pin, move, manage folder, "
            "archive and delete notes"
        ),
    },
    "web-save": {
        "name": "Web Save",
        "description": "Save webpages as clean markdown",
    },
    "web-search": {
        "name": "Web Search",
        "description": "Search the live web for up-to-date information",
    },
    "subdomain-discover": {
        "name": "Subdomain Discovery",
        "description": "Find subdomains using DNS and certificate sources",
    },
    "web-crawler-policy": {
        "name": "Crawler Policy",
        "description": "Analyze robots.txt and llms.txt access policies",
    },
    "audio-transcribe": {
        "name": "Audio Transcription",
        "description": "Transcribe audio files into text and save the transcripts",
    },
    "youtube-download": {
        "name": "YouTube",
        "description": "Save YouTube videos",
    },
    "youtube-transcribe": {
        "name": "YouTube Transcription",
        "description": "Transcribe YouTube videos into text and save the transcripts",
    },
    "skill-creator": {
        "name": "Skill Creator",
        "description": "Guide for creating and updating skills",
    },
    "ui-theme": {
        "name": "UI Theme",
        "description": "Allow {name} to switch between light and dark mode",
    },
    "prompt-preview": {
        "name": "Prompt Preview",
        "description": "Generate the current system prompt output for preview",
    },
    "assistant-identity": {
        "name": "Assistant Identity",
        "description": "Read and update assistant-managed identity settings",
        "show_required_badge": False,
    },
    "assistant-soul": {
        "name": "Assistant Soul",
        "description": "Read and update assistant-managed soul guidance settings",
        "show_required_badge": False,
    },
    "settings-profile-user": {
        "name": "Settings Profile/User",
        "description": "Read and update profile and user settings fields",
    },
    "settings-other-preferences": {
        "name": "Settings",
        "description": "Update local Other settings preferences",
    },
    "memory": {
        "name": "Memory",
        "description": "Store and manage persistent memories",
    },
    "tasks": {
        "name": "Tasks",
        "description": (
            "Search, read, create, complete, defer, organize and delete tasks"
        ),
    },
}

REQUIRED_SKILLS = {
    "assistant-identity",
    "assistant-soul",
}

STANDARD_SKILLS = {
    "files",
    "notes",
    "tasks",
    "web-save",
    "web-search",
    "memory",
    "settings-profile-user",
    "ui-theme",
    "prompt-preview",
    "settings-other-preferences",
}

STORE_SKILLS = {
    "audio-transcribe",
    "youtube-download",
    "youtube-transcribe",
    "subdomain-discover",
    "web-crawler-policy",
}

EXPOSED_SKILLS = REQUIRED_SKILLS | STANDARD_SKILLS | STORE_SKILLS

NON_TOGGLEABLE_SKILLS = set(REQUIRED_SKILLS)
INSTALLABLE_SKILLS = set(STORE_SKILLS)
DEFAULT_ENABLED_SKILLS = REQUIRED_SKILLS | STANDARD_SKILLS

SKILL_PROVIDER_DEPENDENCY: dict[str, str] = {
    "audio-transcribe": "openai",
    "youtube-transcribe": "openai",
    "web-crawler-policy": "openai",
}

SKILL_CREDENTIAL_REQUIREMENTS: dict[str, list[dict[str, Any]]] = {
    "audio-transcribe": [
        {
            "provider": "openai",
            "key_kind": "api_key",
            "required": True,
            "source": "provider_or_skill",
        }
    ],
    "youtube-transcribe": [
        {
            "provider": "openai",
            "key_kind": "api_key",
            "required": True,
            "source": "provider_or_skill",
        }
    ],
    "web-crawler-policy": [
        {
            "provider": "openai",
            "key_kind": "api_key",
            "required": False,
            "mode": "llm_report",
            "source": "provider_or_skill",
        }
    ],
}


def canonicalize_skill_id(skill_id: str) -> str:
    """Return canonical skill ID, resolving known legacy aliases."""
    return SKILL_ID_ALIASES.get(skill_id, skill_id)


def get_legacy_skill_ids(skill_id: str) -> list[str]:
    """Return legacy IDs accepted for a canonical skill."""
    canonical = canonicalize_skill_id(skill_id)
    return list(LEGACY_SKILL_IDS.get(canonical, []))


def get_skill_tier(skill_id: str) -> SkillTier:
    """Return tier for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    if canonical in REQUIRED_SKILLS:
        return "required"
    if canonical in STORE_SKILLS:
        return "store"
    return "standard"


def is_skill_user_toggleable(skill_id: str) -> bool:
    """Return whether a skill can be disabled by users."""
    return canonicalize_skill_id(skill_id) not in NON_TOGGLEABLE_SKILLS


def is_skill_installable(skill_id: str) -> bool:
    """Return whether a skill can be installed from Store skills."""
    return canonicalize_skill_id(skill_id) in INSTALLABLE_SKILLS


def is_skill_default_enabled(skill_id: str) -> bool:
    """Return whether a skill defaults to enabled."""
    return canonicalize_skill_id(skill_id) in DEFAULT_ENABLED_SKILLS


def get_provider_dependency(skill_id: str) -> str:
    """Return provider dependency metadata for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    return SKILL_PROVIDER_DEPENDENCY.get(canonical, "none")


def get_credential_requirements(skill_id: str) -> list[dict[str, Any]]:
    """Return credential requirements metadata for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    requirements = SKILL_CREDENTIAL_REQUIREMENTS.get(canonical, [])
    return [dict(requirement) for requirement in requirements]
