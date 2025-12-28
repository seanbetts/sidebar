"""Skill tooling definitions (skill-creator, mcp-builder)."""
from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_skills_definitions() -> dict:
    """Return skill tooling definitions."""
    return {
        "Package Skill": {
            "description": "Package a skill folder into a zip archive.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "skill_dir": {"type": "string", "description": "Path to skill directory"},
                    "output_dir": {"type": "string", "description": "Output directory"},
                },
                "required": ["skill_dir"],
            },
            "skill": "skill-creator",
            "script": "package_skill.py",
            "build_args": pm.build_skill_package_args,
        },
        "Evaluate MCP Server": {
            "description": "Run an MCP evaluation script.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "eval_file": {"type": "string", "description": "Path to evaluation YAML"},
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
            "script": "evaluate_mcp.py",
            "build_args": pm.build_mcp_evaluation_args,
        },
    }
