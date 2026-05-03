"""Conversation tool definitions."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_conversations_definitions() -> dict:
    """Return conversation tool definitions."""
    return {
        "Search Conversations": {
            "description": (
                "Search conversations by title or visible preview text when the "
                "user asks to find a chat."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query for matching conversations.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": (
                            "Maximum number of matching conversations to return."
                        ),
                    },
                },
                "required": ["query"],
            },
            "skill": "conversations",
            "script": "search_conversations.py",
            "build_args": pm.build_conversations_search_args,
        },
        "Open Chat": {
            "description": (
                "Open an existing chat conversation in the app workspace by ID."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "conversation_id": {
                        "type": "string",
                        "description": "Conversation UUID to open.",
                    },
                    "title": {
                        "type": "string",
                        "description": "Optional chat title for the UI handoff.",
                    },
                },
                "required": ["conversation_id"],
            },
            "skill": "conversations",
            "script": None,
            "build_args": None,
        },
        "Rename Conversation": {
            "description": (
                "Rename a conversation by ID only when the user explicitly asks."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "conversation_id": {
                        "type": "string",
                        "description": "Conversation UUID to rename.",
                    },
                    "new_name": {
                        "type": "string",
                        "description": "New conversation title.",
                    },
                },
                "required": ["conversation_id", "new_name"],
            },
            "skill": "conversations",
            "script": "rename_conversation.py",
            "build_args": pm.build_conversations_rename_args,
        },
    }
