"""Skill metadata for display in tool listings."""

SKILL_DISPLAY = {
    "fs": {
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
        "name": "YouTube Download",
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
        "name": "Settings Other Preferences",
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

EXPOSED_SKILLS = {
    "fs",
    "notes",
    "tasks",
    "web-save",
    "web-search",
    "assistant-identity",
    "assistant-soul",
    "settings-profile-user",
    "settings-other-preferences",
    "memory",
    "ui-theme",
    "prompt-preview",
    "audio-transcribe",
    "youtube-download",
    "youtube-transcribe",
    "subdomain-discover",
    "web-crawler-policy",
    "skill-creator",
}

NON_TOGGLEABLE_SKILLS = {
    "assistant-identity",
    "assistant-soul",
}


def is_skill_user_toggleable(skill_id: str) -> bool:
    """Return whether a skill can be disabled by users."""
    return skill_id not in NON_TOGGLEABLE_SKILLS
