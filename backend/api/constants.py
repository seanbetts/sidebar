"""Shared constants for chat and prompt behavior."""

from __future__ import annotations


class ChatConstants:
    """Chat-related configuration constants."""

    # Cache title generation results for 1 hour to limit Gemini calls.
    TITLE_CACHE_TTL_SECONDS = 60 * 60
    # Keep the cache small; 512 entries is ~50KB for typical titles.
    TITLE_CACHE_MAX_ENTRIES = 512
    # Keep titles compact for sidebar display.
    TITLE_MAX_WORDS = 5
    # Prevent tool loops while allowing multi-step workflows.
    MAX_TOOL_ROUNDS = 5


class PromptContextLimits:
    """Prompt size limits for system and open context blocks."""

    # System prompt cap to avoid overlong model inputs.
    MAX_SYSTEM_PROMPT_CHARS = 40000
    # First message prompt cap for concise bootstrapping.
    MAX_FIRST_MESSAGE_CHARS = 8000
    # Open file payload cap for viewer context.
    MAX_OPEN_FILE_CHARS = 12000
    # Attachment payload cap for contextual snippets.
    MAX_ATTACHMENT_CHARS = 8000
