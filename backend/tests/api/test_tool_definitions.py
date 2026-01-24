from api.services.tools.definitions import get_tool_definitions
from api.services.tools.definitions_fs import get_fs_definitions
from api.services.tools.definitions_misc import get_misc_definitions
from api.services.tools.definitions_notes import get_notes_definitions
from api.services.tools.definitions_skills import get_skills_definitions
from api.services.tools.definitions_tasks import get_tasks_definitions
from api.services.tools.definitions_transcription import get_transcription_definitions
from api.services.tools.definitions_web import get_web_definitions


def _assert_definition_contract(definitions: dict):
    assert definitions, "Expected definitions to be non-empty"
    for name, definition in definitions.items():
        assert isinstance(name, str)
        assert name
        assert "description" in definition
        assert isinstance(definition["description"], str)
        assert definition["description"]
        assert "input_schema" in definition
        assert definition["input_schema"]["type"] == "object"
        assert "skill" in definition
        assert "script" in definition
        assert "build_args" in definition
        if definition["skill"] is not None:
            assert isinstance(definition["skill"], str)
        if definition["script"] is not None:
            assert isinstance(definition["script"], str)
        if definition["build_args"] is not None:
            assert callable(definition["build_args"])


def test_individual_definitions_follow_contract():
    for definitions in [
        get_fs_definitions(),
        get_skills_definitions(),
        get_web_definitions(),
        get_transcription_definitions(),
        get_notes_definitions(),
        get_tasks_definitions(),
        get_misc_definitions(),
    ]:
        _assert_definition_contract(definitions)


def test_tool_definitions_have_no_duplicate_names():
    groups = [
        get_fs_definitions(),
        get_skills_definitions(),
        get_web_definitions(),
        get_transcription_definitions(),
        get_notes_definitions(),
        get_tasks_definitions(),
        get_misc_definitions(),
    ]
    expected_total = sum(len(group) for group in groups)
    merged = get_tool_definitions()
    assert len(merged) == expected_total
