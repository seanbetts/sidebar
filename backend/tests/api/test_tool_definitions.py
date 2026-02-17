from pathlib import Path

from api.services.agent.tools.registry import get_tool_definitions
from api.services.tools.definitions_fs import get_fs_definitions
from api.services.tools.definitions_misc import get_misc_definitions
from api.services.tools.definitions_notes import get_notes_definitions
from api.services.tools.definitions_skills import get_skills_definitions
from api.services.tools.definitions_tasks import get_tasks_definitions
from api.services.tools.definitions_transcription import get_transcription_definitions
from api.services.tools.definitions_web import get_web_definitions


def _assert_definition_contract(definitions: dict):
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
        if not definitions:
            continue
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


def test_tool_schemas_disallow_top_level_combinators():
    disallowed = {"oneOf", "anyOf", "allOf"}
    offenders: list[str] = []

    for name, definition in get_tool_definitions().items():
        schema = definition.get("input_schema") or {}
        present = sorted(disallowed.intersection(schema.keys()))
        if present:
            offenders.append(f"{name}: {', '.join(present)}")

    assert offenders == []


def test_skill_tool_scripts_exist_on_disk():
    skills_root = Path(__file__).resolve().parents[2] / "skills"
    assert skills_root.exists()

    for definition in get_tool_definitions().values():
        skill = definition.get("skill")
        script = definition.get("script")
        if not skill or not script:
            continue

        direct_path = skills_root / skill / script
        scripts_path = skills_root / skill / "scripts" / script
        assert direct_path.exists() or scripts_path.exists()


def test_misc_definitions_include_assistant_identity_tools():
    definitions = get_misc_definitions()
    assert "Get Assistant Identity" in definitions
    assert "Update Assistant Identity" in definitions
    assert "Reset Assistant Identity" in definitions
    assert "Get Assistant Soul" in definitions
    assert "Update Assistant Soul" in definitions
    assert "Reset Assistant Soul" in definitions


def test_fs_definitions_include_file_context_menu_parity_tools():
    definitions = get_fs_definitions()
    assert "Rename File" in definitions
    assert "Delete File" in definitions
    assert "Pin File" in definitions


def test_notes_definitions_include_context_menu_parity_tools():
    definitions = get_notes_definitions()
    assert "Rename Note" in definitions
    assert "Archive Note" in definitions
    assert "Download Note" in definitions
    assert "Create Note Folder" in definitions
    assert "Rename Note Folder" in definitions
    assert "Move Note Folder" in definitions
    assert "Delete Note Folder" in definitions


def test_web_definitions_include_context_menu_parity_tools():
    definitions = get_web_definitions()
    assert "Add Website" in definitions
    assert "Rename Website" in definitions
    assert "Download Website" in definitions
    assert "Archive Website" in definitions
    assert "Delete Website" in definitions
    assert "Pin Website" in definitions


def test_skills_definitions_do_not_expose_skill_packaging():
    definitions = get_skills_definitions()
    assert definitions == {}
    assert "Package Skill" not in definitions
    assert "Evaluate MCP Server" not in definitions
