import pytest

from api.services import tool_mapper as tool_mapper_module
from api.services.tool_mapper import ToolMapper


class DummyExecutor:
    def __init__(self):
        self.calls = []

    async def execute(self, skill, script, args, expect_json=True):
        self.calls.append(
            {
                "skill": skill,
                "script": script,
                "args": args,
                "expect_json": expect_json,
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
            "skill": "fs",
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
            "skill": "fs",
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
    assert mapper.executor.calls[0]["args"] == ["/docs/file.txt"]


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
    monkeypatch.setattr(tool_mapper_module.AuditLogger, "log_tool_call", lambda **_: None)

    result = await mapper.execute_tool("Set UI Theme", {"theme": "dark"})
    assert result["success"] is True
    assert result["data"]["theme"] == "dark"


def test_get_claude_tools_filters_skills():
    tools = {
        "Read File": {
            "description": "read file",
            "input_schema": {"type": "object"},
            "skill": "fs",
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
    claude_tools = mapper.get_claude_tools(allowed_skills=["fs"])
    names = {tool["name"] for tool in claude_tools}
    assert mapper.tool_name_reverse["Read File"] in names
    assert mapper.tool_name_reverse["Create Note"] not in names


@pytest.mark.asyncio
async def test_execute_tool_requires_user_id():
    tools = {
        "Read File": {
            "description": "read file",
            "input_schema": {},
            "skill": "fs",
            "script": "read.py",
            "build_args": lambda _: [],
        }
    }
    mapper = _build_mapper(tools)
    result = await mapper.execute_tool("Read File", {})
    assert result["success"] is False
    assert "requires user_id" in result["error"]
