"""Docx tool definitions."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_docx_definitions() -> dict:
    """Return DOCX tool definitions."""
    return {
        "Unpack DOCX": {
            "description": "Unpack a .docx file into an OOXML directory.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string", "description": "Path to .docx file"},
                    "output_dir": {"type": "string", "description": "Output directory"},
                },
                "required": ["input_file", "output_dir"],
            },
            "skill": "docx",
            "script": "ooxml/scripts/unpack.py",
            "build_args": pm.build_docx_unpack_args,
            "expect_json": False,
        },
        "Pack DOCX": {
            "description": "Pack an OOXML directory into a .docx file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                    "output_file": {"type": "string", "description": "Output .docx path"},
                },
                "required": ["input_dir", "output_file"],
            },
            "skill": "docx",
            "script": "ooxml/scripts/pack.py",
            "build_args": pm.build_docx_pack_args,
            "expect_json": False,
        },
        "Validate DOCX": {
            "description": "Validate an unpacked .docx directory against the original file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "unpacked_dir": {"type": "string", "description": "Unpacked OOXML directory"},
                    "original_file": {"type": "string", "description": "Original .docx file"},
                    "verbose": {"type": "boolean", "description": "Verbose output"},
                },
                "required": ["unpacked_dir", "original_file"],
            },
            "skill": "docx",
            "script": "ooxml/scripts/validate.py",
            "build_args": pm.build_docx_validate_args,
            "expect_json": False,
        },
    }
