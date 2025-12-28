from api.services.tools import execution_handlers


def test_handle_ui_theme_rejects_invalid():
    result = execution_handlers.handle_ui_theme({"theme": "blue"})
    assert result["success"] is False
    assert result["error"] == "Invalid theme"


def test_handle_ui_theme_accepts_valid():
    result = execution_handlers.handle_ui_theme({"theme": "dark"})
    assert result == {"success": True, "data": {"theme": "dark"}}


def test_handle_prompt_preview_requires_context():
    result = execution_handlers.handle_prompt_preview(None)
    assert result["success"] is False
    assert result["error"] == "Missing prompt context"


def test_handle_prompt_preview_requires_db_and_user():
    result = execution_handlers.handle_prompt_preview({"db": object()})
    assert result["success"] is False
    assert result["error"] == "Missing database or user context"


def test_handle_prompt_preview_uses_prompt_context_service(monkeypatch):
    from api.services import prompt_context_service

    captured = {}

    def fake_build_prompts(**kwargs):
        captured.update(kwargs)
        return ("system prompt", "first message")

    monkeypatch.setattr(
        prompt_context_service.PromptContextService,
        "build_prompts",
        staticmethod(fake_build_prompts),
    )

    context = {
        "db": object(),
        "user_id": "user-123",
        "open_context": {"foo": "bar"},
        "user_agent": "test-agent",
        "current_location": "test-location",
        "current_location_levels": ["city"],
        "current_weather": "sunny",
    }
    result = execution_handlers.handle_prompt_preview(context)
    assert result["success"] is True
    assert result["data"]["system_prompt"] == "system prompt"
    assert result["data"]["first_message_prompt"] == "first message"
    assert captured["db"] == context["db"]
    assert captured["user_id"] == "user-123"
    assert captured["current_weather"] == "sunny"


def test_handle_memory_tool_requires_context():
    result = execution_handlers.handle_memory_tool(None, {})
    assert result["success"] is False
    assert result["error"] == "Missing memory context"


def test_handle_memory_tool_calls_handler(monkeypatch):
    from api.services import memory_tool_handler

    def fake_execute_command(db, user_id, params):
        return {"success": True, "data": {"command": params["command"]}}

    monkeypatch.setattr(
        memory_tool_handler.MemoryToolHandler,
        "execute_command",
        staticmethod(fake_execute_command),
    )

    result = execution_handlers.handle_memory_tool(
        {"db": object(), "user_id": "user-123"},
        {"command": "view"},
    )
    assert result == {"success": True, "data": {"command": "view"}}
