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
