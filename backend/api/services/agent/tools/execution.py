"""Compatibility wrapper for special-case tool execution handlers."""

from api.services.tools.execution_handlers import (
    handle_memory_tool,
    handle_prompt_preview,
    handle_ui_theme,
)

__all__ = ["handle_ui_theme", "handle_prompt_preview", "handle_memory_tool"]
