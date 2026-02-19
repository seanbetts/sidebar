"""Miscellaneous tool definitions."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_misc_definitions() -> dict:
    """Return miscellaneous tool definitions."""
    return {
        "Set UI Theme": {
            "description": "Set the UI theme to light or dark.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "theme": {"type": "string", "enum": ["light", "dark"]},
                },
                "required": ["theme"],
            },
            "skill": "ui-theme",
            "script": None,
            "build_args": None,
        },
        "Generate Prompts": {
            "description": "Generate the current system prompt output for preview.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "prompt-preview",
            "script": None,
            "build_args": None,
        },
        "Get Assistant Identity": {
            "description": "Fetch the current assistant identity values.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "assistant-identity",
            "script": "get_assistant_identity.py",
            "build_args": pm.build_assistant_identity_get_args,
        },
        "Update Assistant Identity": {
            "description": (
                "Update assistant identity fields such as name, tone, values, "
                "or boundaries."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "tone": {"type": "string"},
                    "values": {"type": "string"},
                    "boundaries": {"type": "string"},
                    "reason": {"type": "string"},
                },
            },
            "skill": "assistant-identity",
            "script": "update_assistant_identity.py",
            "build_args": pm.build_assistant_identity_update_args,
        },
        "Reset Assistant Identity": {
            "description": "Reset assistant identity values back to defaults.",
            "input_schema": {
                "type": "object",
                "properties": {"reason": {"type": "string"}},
            },
            "skill": "assistant-identity",
            "script": "reset_assistant_identity.py",
            "build_args": pm.build_assistant_identity_reset_args,
        },
        "Get Assistant Soul": {
            "description": "Fetch the current assistant soul values.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "assistant-soul",
            "script": "get_assistant_soul.py",
            "build_args": pm.build_assistant_soul_get_args,
        },
        "Update Assistant Soul": {
            "description": (
                "Update assistant soul fields such as purpose, operating principles, "
                "adaptation policy, or success signals."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "purpose": {"type": "string"},
                    "operating_principles": {"type": "string"},
                    "adaptation_policy": {"type": "string"},
                    "success_signals": {"type": "string"},
                    "reason": {"type": "string"},
                },
            },
            "skill": "assistant-soul",
            "script": "update_assistant_soul.py",
            "build_args": pm.build_assistant_soul_update_args,
        },
        "Reset Assistant Soul": {
            "description": "Reset assistant soul values back to defaults.",
            "input_schema": {
                "type": "object",
                "properties": {"reason": {"type": "string"}},
            },
            "skill": "assistant-soul",
            "script": "reset_assistant_soul.py",
            "build_args": pm.build_assistant_soul_reset_args,
        },
        "Get Profile and User Settings": {
            "description": "Fetch current profile and user settings values.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "settings-profile-user",
            "script": "get_profile_user_settings.py",
            "build_args": pm.build_profile_user_settings_get_args,
        },
        "Update Profile and User Settings": {
            "description": (
                "Update profile and user settings fields such as communication style, "
                "working relationship, personal profile fields, and date of birth."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "communication_style": {"type": "string"},
                    "working_relationship": {"type": "string"},
                    "name": {"type": "string"},
                    "job_title": {"type": "string"},
                    "employer": {"type": "string"},
                    "date_of_birth": {
                        "type": "string",
                        "description": "Date string in YYYY-MM-DD format.",
                    },
                    "clear_date_of_birth": {
                        "type": "boolean",
                        "description": "When true, clears date of birth.",
                    },
                    "gender": {"type": "string"},
                    "pronouns": {"type": "string"},
                    "location": {"type": "string"},
                },
            },
            "skill": "settings-profile-user",
            "script": "update_profile_user_settings.py",
            "build_args": pm.build_profile_user_settings_update_args,
        },
        "Upload Profile Image": {
            "description": (
                "Upload a profile image from a local file path into user settings."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Local path to an image file.",
                    },
                    "content_type": {
                        "type": "string",
                        "description": "Optional MIME type (image/*).",
                    },
                },
                "required": ["path"],
            },
            "skill": "settings-profile-user",
            "script": "upload_profile_image.py",
            "build_args": pm.build_profile_image_upload_args,
            "validate_read": True,
        },
        "Remove Profile Image": {
            "description": "Remove the current profile image from user settings.",
            "input_schema": {
                "type": "object",
                "properties": {},
            },
            "skill": "settings-profile-user",
            "script": "delete_profile_image.py",
            "build_args": pm.build_profile_image_delete_args,
        },
        "Set Other Preferences": {
            "description": (
                "Update local Other settings preferences such as temperature units "
                "or biometric unlock preference."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "weather_unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                    },
                    "biometric_unlock_enabled": {"type": "boolean"},
                },
            },
            "skill": "settings-other-preferences",
            "script": None,
            "build_args": None,
        },
        "Memory Tool": {
            "description": (
                "Create, update, and manage persistent memory files. "
                "Paths should start with /memories."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "enum": [
                            "view",
                            "create",
                            "str_replace",
                            "insert",
                            "delete",
                            "rename",
                        ],
                    },
                    "path": {"type": "string"},
                    "view_range": {
                        "type": "array",
                        "items": {"type": "integer"},
                        "minItems": 2,
                        "maxItems": 2,
                    },
                    "file_text": {"type": "string"},
                    "content": {"type": "string"},
                    "old_str": {"type": "string"},
                    "new_str": {"type": "string"},
                    "insert_line": {"type": "integer"},
                    "insert_text": {"type": "string"},
                    "old_path": {"type": "string"},
                    "new_path": {"type": "string"},
                },
                "required": ["command"],
            },
            "skill": "memory",
            "script": None,
            "build_args": None,
        },
    }
