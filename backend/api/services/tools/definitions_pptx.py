"""Pptx tool definitions."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_pptx_definitions() -> dict:
    return {
        "Inventory PPTX": {
            "description": "Generate an inventory report for a PowerPoint file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_pptx": {"type": "string", "description": "Path to .pptx file"},
                    "output_json": {"type": "string", "description": "Output JSON path"},
                    "issues_only": {"type": "boolean", "description": "Only include slides with issues"},
                },
                "required": ["input_pptx", "output_json"],
            },
            "skill": "pptx",
            "script": "pptx/inventory.py",
            "build_args": pm.build_pptx_inventory_args,
        },
        "Render PPTX Thumbnails": {
            "description": "Render PPTX slide thumbnails to PNG.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "input_pptx": {"type": "string", "description": "Path to .pptx file"},
                    "output_prefix": {"type": "string", "description": "Optional output prefix"},
                    "cols": {"type": "integer", "description": "Columns per sheet"},
                    "outline_placeholders": {
                        "type": "boolean",
                        "description": "Include outline placeholders",
                    },
                },
                "required": ["input_pptx"],
            },
            "skill": "pptx",
            "script": "pptx/render_thumbnails.py",
            "build_args": pm.build_pptx_thumbnail_args,
        },
    }
