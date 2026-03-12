"""Skill tooling definitions."""

from __future__ import annotations


def get_skills_definitions() -> dict:
    """Return skill tooling definitions."""
    return {
        "Get Skill Inventory": {
            "description": (
                "List all available skills with their current status. "
                "Use this when the user asks what skills they have, "
                "what sideBar can do, or why a skill is not working."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "filter": {
                        "type": "string",
                        "enum": ["all", "enabled", "disabled", "blocked"],
                        "description": "Filter skills by status. Defaults to all.",
                    },
                },
            },
            "skill": None,
            "script": None,
            "build_args": None,
        },
        "Search Product Knowledge": {
            "description": (
                "Search sideBar's product documentation for detailed information "
                "about features, settings, skills, and how things work. "
                "Use this when the user asks a specific question that needs "
                "more detail than the product knowledge summary provides."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "The search query describing what to look up.",
                    },
                },
                "required": ["query"],
            },
            "skill": None,
            "script": None,
            "build_args": None,
        },
    }
