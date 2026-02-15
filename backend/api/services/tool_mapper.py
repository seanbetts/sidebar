"""Compatibility shim for tool mapping and execution."""

from __future__ import annotations

import api.services.agent.tools.mapper as _agent_mapper

SKILLS_REQUIRING_USER_ID = _agent_mapper.SKILLS_REQUIRING_USER_ID
AuditLogger = _agent_mapper.AuditLogger
handle_memory_tool = _agent_mapper.handle_memory_tool
handle_prompt_preview = _agent_mapper.handle_prompt_preview
handle_ui_theme = _agent_mapper.handle_ui_theme


class ToolMapper(_agent_mapper.ToolMapper):
    """Back-compat wrapper that syncs monkeypatchable module globals."""

    async def execute_tool(
        self,
        name: str,
        parameters: dict,
        allowed_skills: list[str] | None = None,
        context: dict[str, object] | None = None,
    ) -> dict[str, object]:
        """Execute a tool while syncing legacy monkeypatchable module globals."""
        # Keep legacy module-level monkeypatch behavior functional in tests/callers.
        module_globals = vars(_agent_mapper)
        module_globals["AuditLogger"] = AuditLogger
        module_globals["handle_ui_theme"] = handle_ui_theme
        module_globals["handle_prompt_preview"] = handle_prompt_preview
        module_globals["handle_memory_tool"] = handle_memory_tool
        return await super().execute_tool(name, parameters, allowed_skills, context)


__all__ = [
    "ToolMapper",
    "SKILLS_REQUIRING_USER_ID",
    "AuditLogger",
    "handle_ui_theme",
    "handle_prompt_preview",
    "handle_memory_tool",
]
