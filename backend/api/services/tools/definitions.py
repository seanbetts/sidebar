"""Central tool definitions for ToolMapper."""
from __future__ import annotations

from api.services.tools.definitions_docx import get_docx_definitions
from api.services.tools.definitions_fs import get_fs_definitions
from api.services.tools.definitions_misc import get_misc_definitions
from api.services.tools.definitions_notes import get_notes_definitions
from api.services.tools.definitions_pdf import get_pdf_definitions
from api.services.tools.definitions_pptx import get_pptx_definitions
from api.services.tools.definitions_skills import get_skills_definitions
from api.services.tools.definitions_transcription import get_transcription_definitions
from api.services.tools.definitions_web import get_web_definitions
from api.services.tools.definitions_xlsx import get_xlsx_definitions


def get_tool_definitions() -> dict:
    return {
        **get_fs_definitions(),
        **get_docx_definitions(),
        **get_pptx_definitions(),
        **get_pdf_definitions(),
        **get_xlsx_definitions(),
        **get_skills_definitions(),
        **get_web_definitions(),
        **get_transcription_definitions(),
        **get_notes_definitions(),
        **get_misc_definitions(),
    }
