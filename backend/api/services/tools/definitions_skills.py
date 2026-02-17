"""Skill tooling definitions (skill-creator, mcp-builder)."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_skills_definitions() -> dict:
    """Return skill tooling definitions."""
    return {
        "Evaluate MCP Server": {
            "description": "Run an MCP evaluation script.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "eval_file": {
                        "type": "string",
                        "description": "Path to evaluation XML",
                    },
                    "transport": {"type": "string"},
                    "model": {"type": "string"},
                    "command": {"type": "string"},
                    "args": {"type": "array", "items": {"type": "string"}},
                    "env": {"type": "array", "items": {"type": "string"}},
                    "url": {"type": "string"},
                    "headers": {"type": "array", "items": {"type": "string"}},
                    "output": {"type": "string"},
                },
                "required": ["eval_file"],
            },
            "skill": "mcp-builder",
            "script": "evaluation.py",
            "build_args": pm.build_mcp_evaluation_args,
        },
    }
