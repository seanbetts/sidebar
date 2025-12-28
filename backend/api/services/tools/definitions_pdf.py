"""PDF tool definitions."""
from __future__ import annotations


def get_pdf_definitions() -> dict:
    return {
        "Validate PDF": {
            "description": "Validate a PDF file with pdfcpu.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string", "description": "Path to PDF file"},
                },
                "required": ["input_file"],
            },
            "skill": "pdf",
            "script": "validate.py",
            "build_args": lambda p: [p["input_file"]],
            "expect_json": False,
        },
        "Merge PDFs": {
            "description": "Merge multiple PDFs into a single output file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_files": {"type": "array", "items": {"type": "string"}},
                    "output_file": {"type": "string"},
                },
                "required": ["input_files", "output_file"],
            },
            "skill": "pdf",
            "script": "merge.py",
            "build_args": lambda p: [*p["input_files"], p["output_file"]],
            "expect_json": False,
        },
        "Split PDF": {
            "description": "Split a PDF by page range.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string"},
                    "output_dir": {"type": "string"},
                    "pages": {"type": "string", "description": "Page ranges to extract"},
                },
                "required": ["input_file", "output_dir"],
            },
            "skill": "pdf",
            "script": "split.py",
            "build_args": lambda p: [p["input_file"], p["output_dir"], p.get("pages", "")],
            "expect_json": False,
        },
        "Extract PDF Text": {
            "description": "Extract text from a PDF file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_file": {"type": "string"},
                },
                "required": ["input_file"],
            },
            "skill": "pdf",
            "script": "extract_text.py",
            "build_args": lambda p: [p["input_file"]],
            "expect_json": False,
        },
    }
