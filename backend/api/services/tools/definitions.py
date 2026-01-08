"""Central tool definitions for ToolMapper."""

from __future__ import annotations

from api.services.tools.definitions_fs import get_fs_definitions
from api.services.tools.definitions_misc import get_misc_definitions
from api.services.tools.definitions_notes import get_notes_definitions
from api.services.tools.definitions_skills import get_skills_definitions
from api.services.tools.definitions_transcription import get_transcription_definitions
from api.services.tools.definitions_web import get_web_definitions


def get_tool_definitions() -> dict:
    """Aggregate tool definitions for ToolMapper.

    Returns:
        Dictionary of tool definitions keyed by tool name.
    """
    return {
        **get_fs_definitions(),
        **get_skills_definitions(),
        **get_web_definitions(),
        **get_transcription_definitions(),
        **get_notes_definitions(),
        **get_misc_definitions(),
    }
