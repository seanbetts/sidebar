"""Prompt configuration loader and constants."""
from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

_PROMPT_CONFIG_PATH = Path(__file__).resolve().parent / "config" / "prompts.yaml"


def load_prompt_config() -> dict[str, Any]:
    """Load prompt configuration from YAML."""
    if not _PROMPT_CONFIG_PATH.exists():
        raise FileNotFoundError(f"Prompt config not found at {_PROMPT_CONFIG_PATH}")
    data = yaml.safe_load(_PROMPT_CONFIG_PATH.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError("Prompt config must be a mapping.")
    return data


_PROMPT_CONFIG = load_prompt_config()

DEFAULT_COMMUNICATION_STYLE = _PROMPT_CONFIG["default_communication_style"]
DEFAULT_WORKING_RELATIONSHIP = _PROMPT_CONFIG["default_working_relationship"]
SYSTEM_PROMPT_TEMPLATE = _PROMPT_CONFIG["system_prompt_template"]
CONTEXT_GUIDANCE_TEMPLATE = _PROMPT_CONFIG["context_guidance_template"]
FIRST_MESSAGE_TEMPLATE = _PROMPT_CONFIG["first_message_template"]
RECENT_ACTIVITY_WRAPPER_TEMPLATE = _PROMPT_CONFIG["recent_activity_wrapper_template"]
RECENT_ACTIVITY_EMPTY_TEXT = _PROMPT_CONFIG["recent_activity_empty_text"]
RECENT_ACTIVITY_NOTES_HEADER = _PROMPT_CONFIG["recent_activity_notes_header"]
RECENT_ACTIVITY_WEBSITES_HEADER = _PROMPT_CONFIG["recent_activity_websites_header"]
RECENT_ACTIVITY_CHATS_HEADER = _PROMPT_CONFIG["recent_activity_chats_header"]
RECENT_ACTIVITY_FILES_HEADER = _PROMPT_CONFIG["recent_activity_files_header"]
CURRENT_OPEN_WRAPPER_TEMPLATE = _PROMPT_CONFIG["current_open_wrapper_template"]
CURRENT_OPEN_EMPTY_TEXT = _PROMPT_CONFIG["current_open_empty_text"]
CURRENT_OPEN_NOTE_HEADER = _PROMPT_CONFIG["current_open_note_header"]
CURRENT_OPEN_WEBSITE_HEADER = _PROMPT_CONFIG["current_open_website_header"]
CURRENT_OPEN_FILE_HEADER = _PROMPT_CONFIG["current_open_file_header"]
CURRENT_OPEN_ATTACHMENTS_HEADER = _PROMPT_CONFIG["current_open_attachments_header"]
CURRENT_OPEN_CONTENT_HEADER = _PROMPT_CONFIG["current_open_content_header"]
SUPPORTED_VARIABLES = set(_PROMPT_CONFIG.get("supported_variables", []))
