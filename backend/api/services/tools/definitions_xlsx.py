"""Xlsx tool definitions."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_xlsx_definitions() -> dict:
    """Return XLSX tool definitions."""
    return {
        "Recalculate XLSX": {
            "description": "Recalculate formulas in an .xlsx file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "file_path": {"type": "string", "description": "Path to .xlsx file"},
                    "timeout_seconds": {"type": "integer", "description": "Timeout in seconds (optional)"},
                },
                "required": ["file_path"],
            },
            "skill": "xlsx",
            "script": "recalculate.py",
            "build_args": pm.build_xlsx_recalc_args,
        },
    }
