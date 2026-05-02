from api.services.ai.tool_result_normalizer import normalize_tool_result


def test_normalize_tool_result_adds_summary_and_entities_touched_for_website_rename() -> (
    None
):
    result = {
        "success": True,
        "data": {
            "id": "website-1",
            "title": "Renamed website",
        },
    }

    normalized = normalize_tool_result("Rename Website", result)

    assert normalized["success"] is True
    assert normalized["data"] == result["data"]
    assert isinstance(normalized["summary"], str)
    assert normalized["summary"]
    assert normalized["entities_touched"] == [
        {
            "entity_type": "website",
            "entity_id": "website-1",
            "change": "renamed",
        }
    ]


def test_normalize_tool_result_adds_collection_summary_for_profile_update() -> None:
    result = {
        "success": True,
        "data": {
            "settings": {
                "name": "Sean",
                "job_title": "Engineer",
                "location": "Austin, TX",
            }
        },
    }

    normalized = normalize_tool_result("Update Profile and User Settings", result)

    assert normalized["success"] is True
    assert normalized["data"] == result["data"]
    assert isinstance(normalized["summary"], str)
    assert normalized["summary"]
    assert normalized["entities_touched"] == [
        {
            "entity_type": "profile",
            "entity_id": "current",
            "change": "updated",
        },
        {
            "entity_type": "preferences",
            "entity_id": "current",
            "change": "updated",
        },
    ]


def test_normalize_tool_result_adds_summary_for_get_note_open() -> None:
    result = {
        "success": True,
        "data": {
            "id": "note-1",
            "title": "Orion - Project Brief",
        },
    }

    normalized = normalize_tool_result("Get Note", result)

    assert normalized["summary"] == "Opened note Orion - Project Brief"
    assert normalized["entities_touched"] == [
        {
            "entity_type": "note",
            "entity_id": "note-1",
            "change": "opened",
        }
    ]


def test_normalize_tool_result_leaves_non_mutating_tool_result_unchanged() -> None:
    result = {
        "success": True,
        "data": {
            "system_prompt": "system",
            "first_message_prompt": "first",
        },
    }

    normalized = normalize_tool_result("Generate Prompts", result)

    assert normalized == result
