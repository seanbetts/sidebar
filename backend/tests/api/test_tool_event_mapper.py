from api.services.ai.tool_event_mapper import tool_side_effect_events


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


def test_tool_side_effect_events_emits_workspace_patch_events_from_array() -> None:
    events = tool_side_effect_events(
        "Unknown Tool",
        {
            "success": True,
            "data": {
                "workspace_patches": [
                    {"version": 1, "operations": [{"op": "swap_panes"}]},
                    {"version": 1, "operations": [{"op": "close_pane", "pane": "secondary"}]},
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


def test_tool_side_effect_events_maps_conversation_title_updated() -> None:
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
            "type": "conversation_title_updated",
            "data": {
                "id": "conv-1",
                "title": "Renamed",
                "titleGenerated": False,
                "updatedAt": "2026-03-28T12:00:00Z",
            },
        }
    ]


def test_tool_side_effect_events_maps_edit_note_snapshot() -> None:
    events = tool_side_effect_events(
        "Edit Note",
        {
            "success": True,
            "data": {
                "id": "note-1",
                "title": "Renamed",
                "name": "Renamed",
                "path": "note-1",
                "content": "Renamed\nBody",
                "updated_at": "2026-03-30T15:10:00Z",
            },
        },
    )

    assert events == [
        {
            "type": "note_updated",
            "data": {
                "id": "note-1",
                "title": "Renamed",
                "name": "Renamed",
                "path": "note-1",
                "content": "Renamed\nBody",
                "updated_at": "2026-03-30T15:10:00Z",
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
            "type": "website_renamed",
            "data": {
                "id": "website-1",
                "title": "Renamed website",
            },
        }
    ]
