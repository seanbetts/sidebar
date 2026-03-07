"""Skill metadata and catalog helpers for tool listings."""

from __future__ import annotations

from typing import Any, Literal

CATALOG_VERSION = 9

SkillTier = Literal["required", "standard", "store"]

SKILL_ID_ALIASES: dict[str, str] = {}

LEGACY_SKILL_IDS: dict[str, list[str]] = {}

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
    },
    "assistant-soul": {
        "name": "Assistant Soul",
        "description": "Read and update assistant-managed soul guidance settings",
    },
    "settings-profile-user": {
        "name": "Settings Profile/User",
        "description": "Read and update profile and user settings fields",
    },
    "settings-other-preferences": {
        "name": "Settings",
        "description": "Update local Other settings preferences",
    },
    "product-feedback": {
        "name": "Product Feedback",
        "description": "Submit bug reports and feature requests to the product team",
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
    "product-feedback",
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

SKILL_REQUIRED_TOOLSETS: dict[str, tuple[str, ...]] = {
    "files": ("files",),
    "notes": ("notes",),
    "tasks": ("tasks",),
    "web-save": ("web",),
    "web-search": ("web_search",),
    "memory": ("memory",),
    "settings-profile-user": ("settings",),
    "ui-theme": ("ui_theme",),
    "prompt-preview": ("prompt_preview",),
    "settings-other-preferences": ("settings",),
    "audio-transcribe": ("transcription",),
    "youtube-download": ("web",),
    "youtube-transcribe": ("transcription",),
    "subdomain-discover": ("web",),
    "web-crawler-policy": ("web", "llm_report"),
    "assistant-identity": ("assistant_identity",),
    "assistant-soul": ("assistant_soul",),
    "product-feedback": ("product_feedback",),
}

SKILL_TAGS: dict[str, tuple[str, ...]] = {
    "files": ("documents", "workspace"),
    "notes": ("notes", "knowledge"),
    "tasks": ("tasks", "planning"),
    "web-save": ("web", "capture"),
    "web-search": ("web", "search"),
    "memory": ("memory", "system"),
    "audio-transcribe": ("audio", "transcription"),
    "youtube-download": ("youtube", "media"),
    "youtube-transcribe": ("youtube", "transcription"),
    "subdomain-discover": ("web", "security"),
    "web-crawler-policy": ("web", "analysis"),
}

SKILL_TRIGGERS: dict[str, tuple[str, ...]] = {
    "files": ("file", "folder", "workspace"),
    "notes": ("note", "notes"),
    "tasks": ("task", "todo", "project"),
    "web-save": ("save page", "capture page"),
    "web-search": ("search web", "look up"),
    "memory": ("remember", "memory"),
    "audio-transcribe": ("transcribe audio", "audio transcript"),
    "youtube-download": ("download youtube", "save youtube"),
    "youtube-transcribe": ("transcribe youtube", "youtube transcript"),
    "subdomain-discover": ("subdomain", "dns"),
    "web-crawler-policy": ("robots", "llms.txt"),
}

SKILL_TOKEN_ESTIMATES: dict[str, int] = {
    "files": 450,
    "notes": 450,
    "tasks": 400,
    "web-save": 350,
    "web-search": 300,
    "memory": 250,
    "settings-profile-user": 300,
    "ui-theme": 200,
    "prompt-preview": 220,
    "settings-other-preferences": 250,
    "audio-transcribe": 550,
    "youtube-download": 420,
    "youtube-transcribe": 560,
    "subdomain-discover": 500,
    "web-crawler-policy": 520,
    "assistant-identity": 250,
    "assistant-soul": 250,
    "product-feedback": 220,
}

SKILL_INSTRUCTION_REFS: dict[str, str] = {
    skill_id: f"skills/{skill_id}/SKILL.md" for skill_id in EXPOSED_SKILLS
}

SKILL_EXAMPLE_REFS: dict[str, tuple[str, ...]] = {
    "audio-transcribe": ("skills/audio-transcribe/examples/basic.md",),
    "youtube-transcribe": ("skills/youtube-transcribe/examples/basic.md",),
    "web-crawler-policy": ("skills/web-crawler-policy/examples/basic.md",),
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


def get_required_toolsets(skill_id: str) -> list[str]:
    """Return internal toolset requirements for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    return list(SKILL_REQUIRED_TOOLSETS.get(canonical, ()))


def get_skill_tags(skill_id: str) -> list[str]:
    """Return compact discovery tags for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    return list(SKILL_TAGS.get(canonical, ()))


def get_skill_triggers(skill_id: str) -> list[str]:
    """Return compact discovery triggers for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    return list(SKILL_TRIGGERS.get(canonical, ()))


def get_skill_token_estimate(skill_id: str) -> int:
    """Return estimated prompt cost for loading a skill."""
    canonical = canonicalize_skill_id(skill_id)
    return int(SKILL_TOKEN_ESTIMATES.get(canonical, 200))


def get_instruction_ref(skill_id: str) -> str:
    """Return the stable instruction reference for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    return SKILL_INSTRUCTION_REFS.get(canonical, f"skills/{canonical}/SKILL.md")


def get_example_refs(skill_id: str) -> list[str]:
    """Return example reference paths for a skill."""
    canonical = canonicalize_skill_id(skill_id)
    return list(SKILL_EXAMPLE_REFS.get(canonical, ()))
