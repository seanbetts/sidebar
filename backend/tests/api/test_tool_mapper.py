import pytest
from api.services.ai.policy import AICapabilityUnavailableError
from api.services.ai.gateway import TranscriptionResolution
from api.services.agent.tools import mapper as tool_mapper_module
from api.services.agent.tools.mapper import ToolMapper


class DummyExecutor:
    def __init__(self):
        self.calls = []

    async def execute(
        self,
        skill,
        script,
        args,
        expect_json=True,
        env_overrides=None,
    ):
        self.calls.append(
            {
                "skill": skill,
                "script": script,
                "args": args,
                "expect_json": expect_json,
                "env_overrides": env_overrides,
            }
        )
        return {"success": True, "data": {"value": "ok"}}


class DummyPathValidator:
    def __init__(self):
        self.read_paths = []
        self.write_paths = []

    def validate_write_path(self, path):
        self.write_paths.append(path)

    def validate_read_path(self, path):
        self.read_paths.append(path)


def _build_mapper(tools):
    mapper = ToolMapper()
    mapper.tools = tools
    mapper._build_tool_name_maps()
    mapper.executor = DummyExecutor()
    mapper.path_validator = DummyPathValidator()
    return mapper


@pytest.mark.asyncio
async def test_execute_tool_unknown():
    mapper = _build_mapper({})
    result = await mapper.execute_tool("unknown", {})
    assert result["success"] is False
    assert "Unknown tool" in result["error"]


@pytest.mark.asyncio
async def test_execute_tool_blocks_disabled_skill():
    tools = {
        "Write File": {
            "description": "write file",
            "input_schema": {},
            "skill": "files",
            "script": "write.py",
            "build_args": lambda _: [],
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool("Write File", {}, allowed_skills=["notes"])
    assert result["success"] is False
    assert "Skill disabled" in result["error"]


@pytest.mark.asyncio
async def test_execute_tool_validates_write_path():
    tools = {
        "Write File": {
            "description": "write file",
            "input_schema": {},
            "skill": "files",
            "script": "write.py",
            "build_args": lambda params: [params["path"]],
            "validate_write": True,
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool(
        "Write File",
        {"path": "/docs/file.txt"},
        context={"user_id": "user-1"},
    )
    assert result["success"] is True
    assert mapper.path_validator.write_paths == ["/docs/file.txt"]
    assert mapper.executor.calls[0]["args"] == ["/docs/file.txt", "--user-id", "user-1"]


@pytest.mark.asyncio
async def test_execute_tool_ui_theme_handler(monkeypatch):
    tools = {
        "Set UI Theme": {
            "description": "theme",
            "input_schema": {},
            "skill": None,
            "script": "",
            "build_args": lambda _: [],
        }
    }
    mapper = _build_mapper(tools)

    def fake_handle_ui_theme(params):
        return {"success": True, "data": {"theme": params.get("theme")}}

    monkeypatch.setattr(tool_mapper_module, "handle_ui_theme", fake_handle_ui_theme)
    monkeypatch.setattr(
        tool_mapper_module.AuditLogger, "log_tool_call", lambda **_: None
    )

    result = await mapper.execute_tool("Set UI Theme", {"theme": "dark"})
    assert result["success"] is True
    assert result["data"]["theme"] == "dark"


def test_get_claude_tools_filters_skills():
    tools = {
        "Read File": {
            "description": "read file",
            "input_schema": {"type": "object"},
            "skill": "files",
            "script": "read.py",
            "build_args": lambda _: [],
        },
        "Create Note": {
            "description": "note",
            "input_schema": {"type": "object"},
            "skill": "notes",
            "script": "create.py",
            "build_args": lambda _: [],
        },
    }
    mapper = _build_mapper(tools)
    claude_tools = mapper.get_claude_tools(allowed_skills=["files"])
    names = {tool["name"] for tool in claude_tools}
    assert mapper.tool_name_reverse["Read File"] in names
    assert mapper.tool_name_reverse["Create Note"] not in names


def test_get_claude_tools_filters_out_disabled_skill():
    tools = {
        "Read File": {
            "description": "read file",
            "input_schema": {"type": "object"},
            "skill": "files",
            "script": "read.py",
            "build_args": lambda _: [],
        }
    }
    mapper = _build_mapper(tools)
    claude_tools = mapper.get_claude_tools(allowed_skills=["notes"])
    names = {tool["name"] for tool in claude_tools}
    assert mapper.tool_name_reverse["Read File"] not in names


def test_get_claude_tools_does_not_treat_fs_as_files():
    tools = {
        "Read File": {
            "description": "read file",
            "input_schema": {"type": "object"},
            "skill": "files",
            "script": "read.py",
            "build_args": lambda _: [],
        }
    }
    mapper = _build_mapper(tools)
    claude_tools = mapper.get_claude_tools(allowed_skills=["fs"])
    assert claude_tools == []


@pytest.mark.asyncio
async def test_execute_tool_requires_user_id():
    tools = {
        "Read File": {
            "description": "read file",
            "input_schema": {},
            "skill": "files",
            "script": "read.py",
            "build_args": lambda _: [],
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool("Read File", {})
    assert result["success"] is False
    assert "requires user_id" in result["error"]


@pytest.mark.asyncio
async def test_execute_tool_appends_user_id_for_assistant_identity_skill():
    tools = {
        "Update Assistant Identity": {
            "description": "update assistant identity",
            "input_schema": {},
            "skill": "assistant-identity",
            "script": "update_assistant_identity.py",
            "build_args": lambda _params: ["--name", "Navigator"],
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool(
        "Update Assistant Identity",
        {"name": "Navigator"},
        context={"user_id": "user-1"},
    )
    assert result["success"] is True
    assert mapper.executor.calls[0]["args"] == [
        "--name",
        "Navigator",
        "--user-id",
        "user-1",
    ]


@pytest.mark.asyncio
async def test_execute_tool_appends_user_id_for_assistant_soul_skill():
    tools = {
        "Update Assistant Soul": {
            "description": "update assistant soul",
            "input_schema": {},
            "skill": "assistant-soul",
            "script": "update_assistant_soul.py",
            "build_args": lambda _params: ["--purpose", "Help me iterate with confidence."],
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool(
        "Update Assistant Soul",
        {"purpose": "Help me iterate with confidence."},
        context={"user_id": "user-1"},
    )
    assert result["success"] is True
    assert mapper.executor.calls[0]["args"] == [
        "--purpose",
        "Help me iterate with confidence.",
        "--user-id",
        "user-1",
    ]


@pytest.mark.asyncio
async def test_execute_tool_appends_user_id_for_profile_user_settings_skill():
    tools = {
        "Update Profile and User Settings": {
            "description": "update profile and user settings",
            "input_schema": {},
            "skill": "settings-profile-user",
            "script": "update_profile_user_settings.py",
            "build_args": lambda _params: ["--name", "Sean"],
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool(
        "Update Profile and User Settings",
        {"name": "Sean"},
        context={"user_id": "user-1"},
    )
    assert result["success"] is True
    assert mapper.executor.calls[0]["args"] == [
        "--name",
        "Sean",
        "--user-id",
        "user-1",
    ]


@pytest.mark.asyncio
async def test_execute_tool_injects_product_feedback_context_fields():
    captured_params: dict[str, object] = {}

    def _build_args(params):
        captured_params.update(params)
        return ["--summary", "Unable to rename a task"]

    tools = {
        "Submit Bug Report": {
            "description": "submit bug report",
            "input_schema": {},
            "skill": "product-feedback",
            "script": "submit_feedback.py",
            "build_args": _build_args,
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool(
        "Submit Bug Report",
        {"summary": "Unable to rename a task"},
        context={
            "user_id": "user-1",
            "user_agent": "Mozilla/5.0 (Macintosh)",
            "conversation_id": "conv-1",
            "user_message_id": "msg-1",
            "assistant_message_id": "asst-1",
        },
    )
    assert result["success"] is True
    assert captured_params["user_id"] == "user-1"
    assert captured_params["conversation_id"] == "conv-1"
    assert captured_params["user_message_id"] == "msg-1"
    assert captured_params["assistant_message_id"] == "asst-1"
    assert mapper.executor.calls[0]["args"] == [
        "--summary",
        "Unable to rename a task",
        "--user-id",
        "user-1",
    ]


@pytest.mark.asyncio
async def test_execute_tool_other_preferences_handler(monkeypatch):
    tools = {
        "Set Other Preferences": {
            "description": "preferences",
            "input_schema": {},
            "skill": "settings-other-preferences",
            "script": None,
            "build_args": None,
        }
    }
    mapper = _build_mapper(tools)

    def fake_handle_other_preferences(params):
        return {"success": True, "data": params}

    monkeypatch.setattr(
        tool_mapper_module,
        "handle_other_preferences",
        fake_handle_other_preferences,
    )
    monkeypatch.setattr(
        tool_mapper_module.AuditLogger, "log_tool_call", lambda **_: None
    )

    result = await mapper.execute_tool(
        "Set Other Preferences",
        {"weather_unit": "fahrenheit", "biometric_unlock_enabled": True},
    )
    assert result["success"] is True
    assert result["data"]["weather_unit"] == "fahrenheit"
    assert result["data"]["biometric_unlock_enabled"] is True


@pytest.mark.asyncio
async def test_execute_tool_injects_transcription_model_from_gateway(monkeypatch):
    tools = {
        "Transcribe Audio": {
            "description": "transcribe audio",
            "input_schema": {},
            "skill": "audio-transcribe",
            "script": "transcribe_audio.py",
            "build_args": lambda params: [params["model"]],
        }
    }
    mapper = _build_mapper(tools)
    monkeypatch.setattr(
        mapper.ai_gateway,
        "resolve_transcription",
        lambda **_kwargs: TranscriptionResolution(
            provider="openai",
            model="gpt-4o-transcribe",
            api_key="sk-test-openai",
        ),
    )

    result = await mapper.execute_tool(
        "Transcribe Audio",
        {"file_path": "files/audio.m4a"},
        context={"user_id": "user-1"},
    )
    assert result["success"] is True
    assert mapper.executor.calls[0]["args"] == [
        "gpt-4o-transcribe",
        "--user-id",
        "user-1",
    ]
    assert mapper.executor.calls[0]["env_overrides"] == {
        "OPENAI_API_KEY": "sk-test-openai"
    }


def test_get_skill_inventory_tool_defined():
    """The Get Skill Inventory tool should be in the definitions."""
    from api.services.tools.definitions_skills import get_skills_definitions

    defs = get_skills_definitions()
    assert "Get Skill Inventory" in defs
    schema = defs["Get Skill Inventory"]["input_schema"]
    assert schema["type"] == "object"


def test_search_product_knowledge_tool_defined():
    """The Search Product Knowledge tool should be in the definitions."""
    from api.services.tools.definitions_skills import get_skills_definitions

    defs = get_skills_definitions()
    assert "Search Product Knowledge" in defs
    schema = defs["Search Product Knowledge"]["input_schema"]
    assert "query" in schema["properties"]
    assert "query" in schema["required"]


@pytest.mark.asyncio
async def test_execute_get_skill_inventory():
    """Get Skill Inventory should return structured skill data."""
    from api.services.tools.definitions_skills import get_skills_definitions
    mapper = _build_mapper(get_skills_definitions())
    result = await mapper.execute_tool(
        "Get_Skill_Inventory",
        {"filter": "all"},
        context={
            "user_id": "test-user",
            "enabled_skill_ids": ["notes", "tasks"],
            "runtime_capabilities": [
                {"skill_id": "notes", "availability_status": "ready"},
                {"skill_id": "tasks", "availability_status": "ready"},
            ],
        },
    )
    assert result["success"] is True
    skills = result["data"]["skills"]
    assert any(s["skill_id"] == "notes" for s in skills)


@pytest.mark.asyncio
async def test_execute_search_product_knowledge():
    """Search Product Knowledge should return matching docs."""
    from api.services.tools.definitions_skills import get_skills_definitions
    from api.services.knowledge.provider import init_docs_indexer
    from pathlib import Path
    import tempfile
    import api.services.knowledge.provider as _knowledge_provider

    with tempfile.TemporaryDirectory() as tmp:
        docs_root = Path(tmp)
        (docs_root / "notes.md").write_text(
            "---\ntitle: Notes\nsummary: Capture and organise your thoughts.\n"
            "tags: [skills]\naudience: user\nsurfaces: [internal-knowledge]\n---\n\nContent.\n"
        )
        init_docs_indexer(docs_root)
        try:
            mapper = _build_mapper(get_skills_definitions())
            result = await mapper.execute_tool(
                "Search_Product_Knowledge",
                {"query": "notes"},
                context={"user_id": "test-user"},
            )
            assert result["success"] is True
            assert "results" in result["data"]
        finally:
            _knowledge_provider._indexer = None


def test_internal_tools_always_included():
    """Tools with skill=None should always be included regardless of allowed_skills."""
    from api.services.tools.definitions_skills import get_skills_definitions

    mapper = _build_mapper(get_skills_definitions())
    tools = mapper.get_claude_tools(allowed_skills=["notes"])
    tool_names = [t["name"] for t in tools]
    assert "Get_Skill_Inventory" in tool_names
    assert "Search_Product_Knowledge" in tool_names


@pytest.mark.asyncio
async def test_execute_tool_returns_error_when_transcription_unavailable(monkeypatch):
    tools = {
        "Transcribe Audio": {
            "description": "transcribe audio",
            "input_schema": {},
            "skill": "audio-transcribe",
            "script": "transcribe_audio.py",
            "build_args": lambda params: [params["file_path"]],
        }
    }
    mapper = _build_mapper(tools)

    def _raise_unavailable(**_kwargs):
        raise AICapabilityUnavailableError("Capability unavailable")

    monkeypatch.setattr(mapper.ai_gateway, "resolve_transcription", _raise_unavailable)

    result = await mapper.execute_tool(
        "Transcribe Audio",
        {"file_path": "files/audio.m4a"},
        context={"user_id": "user-1"},
    )
    assert result["success"] is False
    assert "Capability unavailable" in result["error"]
