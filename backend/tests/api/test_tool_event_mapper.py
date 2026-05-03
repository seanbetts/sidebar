from api.services.ai.tool_event_mapper import tool_side_effect_events


def test_tool_side_effect_events_maps_create_note_with_workspace_opening() -> None:
    events = tool_side_effect_events(
        "Create Note",
        {
            "success": True,
            "data": {
                "id": "note-1",
                "title": "Test",
                "folder": "",
                "path": "note-1",
            },
        },
    )

    assert events == [
        {
            "type": "entity_changed",
            "data": {
                "entity_type": "note",
                "entity_id": "note-1",
                "change": "created",
                "patch": {
                    "id": "note-1",
                    "title": "Test",
                    "folder": "",
                    "path": "note-1",
                    "open_in_workspace": True,
                },
                "invalidate": ["notes", "note:note-1"],
            },
        }
    ]


def test_tool_side_effect_events_maps_get_note_with_workspace_opening() -> None:
    events = tool_side_effect_events(
        "Get Note",
        {
            "success": True,
            "data": {
                "id": "note-1",
                "title": "Orion - Project Brief",
                "path": "Projects/Orion",
                "updated_at": "2026-05-02T20:00:00Z",
            },
        },
    )

    assert events == [
        {
            "type": "entity_changed",
            "data": {
                "entity_type": "note",
                "entity_id": "note-1",
                "change": "opened",
                "patch": {
                    "id": "note-1",
                    "title": "Orion - Project Brief",
                    "path": "Projects/Orion",
                    "updated_at": "2026-05-02T20:00:00Z",
                    "open_in_workspace": True,
                },
                "invalidate": ["notes", "note:note-1"],
            },
        }
    ]


def test_tool_side_effect_events_emits_workspace_patch_event() -> None:
    events = tool_side_effect_events(
        "Unknown Tool",
        {
            "success": True,
            "data": {
                "workspace_patch": {
                    "version": 1,
                    "operations": [{"op": "swap_panes"}],
                }
            },
        },
    )

    assert events == [
        {
            "type": "workspace_patch",
            "data": {"version": 1, "operations": [{"op": "swap_panes"}]},
        }
    ]


def test_tool_side_effect_events_emits_open_entity_workspace_patch() -> None:
    events = tool_side_effect_events(
        "Open Note",
        {
            "success": True,
            "data": {
                "workspace_patch": {
                    "version": 1,
                    "operations": [
                        {
                            "op": "open_entity",
                            "entity": {
                                "type": "note",
                                "id": "note-123",
                                "title": "Orion — Project Brief",
                            },
                            "route_url": "sidebar://notes/note-123",
                            "section": "notes",
                            "pane": "primary",
                        }
                    ],
                }
            },
        },
    )

    assert events == [
        {
            "type": "workspace_patch",
            "data": {
                "version": 1,
                "operations": [
                    {
                        "op": "open_entity",
                        "entity": {
                            "type": "note",
                            "id": "note-123",
                            "title": "Orion — Project Brief",
                        },
                        "route_url": "sidebar://notes/note-123",
                        "section": "notes",
                        "pane": "primary",
                    }
                ],
            },
        }
    ]


def test_tool_side_effect_events_emits_workspace_patch_events_from_array() -> None:
    events = tool_side_effect_events(
        "Unknown Tool",
        {
            "success": True,
            "data": {
                "workspace_patches": [
                    {"version": 1, "operations": [{"op": "swap_panes"}]},
                    {
                        "version": 1,
                        "operations": [{"op": "close_pane", "pane": "secondary"}],
                    },
                ]
            },
        },
    )

    assert events == [
        {
            "type": "workspace_patch",
            "data": {"version": 1, "operations": [{"op": "swap_panes"}]},
        },
        {
            "type": "workspace_patch",
            "data": {
                "version": 1,
                "operations": [{"op": "close_pane", "pane": "secondary"}],
            },
        },
    ]


def test_tool_side_effect_events_ignores_invalid_workspace_patch_payloads() -> None:
    events = tool_side_effect_events(
        "Unknown Tool",
        {
            "success": True,
            "data": {
                "workspace_patch": {"version": "1", "operations": []},
                "workspace_patches": [
                    {"version": 1, "operations": "swap"},
                    {"version": 1, "operations": [{"op": "swap_panes"}]},
                ],
            },
        },
    )

    assert events == [
        {
            "type": "workspace_patch",
            "data": {"version": 1, "operations": [{"op": "swap_panes"}]},
        }
    ]


def test_tool_side_effect_events_maps_prompt_preview_workspace_actions() -> None:
    events = tool_side_effect_events(
        "Generate Prompts",
        {
            "success": True,
            "data": {
                "system_prompt": "system",
                "first_message_prompt": "first",
                "request_budget_report": {"provider": "anthropic"},
                "workspace_context_menu_actions": [
                    "copy_markdown",
                    "share_text",
                    "download",
                ],
            },
        },
    )

    assert events == [
        {
            "type": "prompt_preview",
            "data": {
                "system_prompt": "system",
                "first_message_prompt": "first",
                "system_prompt_sections": None,
                "first_message_prompt_sections": None,
                "prompt_report": None,
                "request_budget_report": {"provider": "anthropic"},
                "workspace_context_menu_actions": [
                    "copy_markdown",
                    "share_text",
                    "download",
                ],
            },
        }
    ]


def test_tool_side_effect_events_maps_rename_website() -> None:
    events = tool_side_effect_events(
        "Rename Website",
        {
            "success": True,
            "data": {
                "id": "website-1",
                "title": "Renamed website",
            },
        },
    )

    assert events == [
        {
            "type": "entity_changed",
            "data": {
                "entity_type": "website",
                "entity_id": "website-1",
                "change": "renamed",
                "patch": {"title": "Renamed website"},
                "invalidate": ["websites", "website:website-1"],
            },
        }
    ]


def test_tool_side_effect_events_maps_rename_conversation() -> None:
    events = tool_side_effect_events(
        "Rename Conversation",
        {
            "success": True,
            "data": {
                "id": "conv-1",
                "title": "Renamed",
                "titleGenerated": False,
                "updatedAt": "2026-03-28T12:00:00Z",
            },
        },
    )

    assert events == [
        {
            "type": "entity_changed",
            "data": {
                "entity_type": "conversation",
                "entity_id": "conv-1",
                "change": "renamed",
                "patch": {
                    "title": "Renamed",
                    "titleGenerated": False,
                    "updatedAt": "2026-03-28T12:00:00Z",
                },
                "invalidate": ["conversations", "conversation:conv-1"],
            },
        }
    ]


def test_tool_side_effect_events_maps_profile_settings_update() -> None:
    events = tool_side_effect_events(
        "Update Profile and User Settings",
        {
            "success": True,
            "data": {
                "settings": {
                    "name": "Sean",
                    "job_title": "Engineer",
                    "location": "Austin, TX",
                }
            },
        },
    )

    assert events == [
        {
            "type": "collection_invalidated",
            "data": {
                "targets": ["profile", "preferences"],
            },
        }
    ]


def test_tool_side_effect_events_maps_assistant_identity_update() -> None:
    events = tool_side_effect_events(
        "Update Assistant Identity",
        {
            "success": True,
            "data": {
                "assistant_identity": {"name": "Navigator"},
                "assistant_identity_meta": {
                    "updated_at": "2026-02-18T00:00:00Z",
                    "version": 2,
                },
            },
        },
    )

    assert events == [
        {
            "type": "collection_invalidated",
            "data": {
                "targets": ["assistant_settings"],
            },
        }
    ]
