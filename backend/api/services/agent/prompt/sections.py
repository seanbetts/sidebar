"""Compatibility wrapper for prompt section builders."""

from api.prompts import (
    CONTEXT_GUIDANCE_TEMPLATE,
    SUPPORTED_VARIABLES,
    build_first_message_prompt,
    build_open_context_block,
    build_prompt_variables,
    build_recent_activity_block,
    build_system_prompt,
    detect_operating_system,
    resolve_default,
    resolve_template,
)

__all__ = [
    "CONTEXT_GUIDANCE_TEMPLATE",
    "SUPPORTED_VARIABLES",
    "detect_operating_system",
    "resolve_template",
    "resolve_default",
    "build_prompt_variables",
    "build_recent_activity_block",
    "build_open_context_block",
    "build_system_prompt",
    "build_first_message_prompt",
]
