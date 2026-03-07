from api.services.agent.tools import execution as execution_handlers


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
    from api.services.agent.prompt import composer as prompt_context_service
    from api.services.agent import request_assembly_service
    from api.services.agent.request_budget_service import (
        PreparedChatRequest,
        RequestBudgetReport,
    )
    from api.services.ai import policy as ai_policy
    from api.services.ai import registry as ai_registry
    from api.services.settings_service import SettingsService
    from api.services.user_settings_service import UserSettingsService

    captured = {}
    settings_record = object()

    def fake_build_prompts(**kwargs):
        captured.update(kwargs)
        return {
            "system_prompt": {
                "text": "system prompt",
                "max_chars": 40000,
                "total_chars": 13,
                "truncated": False,
                "sections": [],
            },
            "first_message_prompt": {
                "text": "first message",
                "max_chars": 8000,
                "total_chars": 13,
                "truncated": False,
                "sections": [],
            },
            "report": {
                "system_prompt": {
                    "total_chars": 13,
                    "max_chars": 40000,
                    "truncated": False,
                    "sections": [],
                },
                "first_message_prompt": {
                    "total_chars": 13,
                    "max_chars": 8000,
                    "truncated": False,
                    "sections": [],
                },
            },
        }

    def fake_build_assembled_inputs(**kwargs):
        captured["assembled_inputs_kwargs"] = kwargs
        return request_assembly_service.AssembledChatInputs(
            system_prompt="system prompt",
            bootstrap_history=[{"role": "user", "content": "first message"}],
            conversation_history=[],
            current_user_message="",
            prompt_bundle=fake_build_prompts(**kwargs),
        )

    def fake_build_prepared_request(**kwargs):
        captured["prepared_request_kwargs"] = kwargs
        return PreparedChatRequest(
            provider="anthropic",
            model="claude-sonnet-4-6",
            system_prompt="system prompt",
            bootstrap_history=[{"role": "user", "content": "first message"}],
            conversation_history=[],
            current_user_message="",
            tool_definitions=[{"name": "lookup_note"}],
            budget_report=RequestBudgetReport(
                provider="anthropic",
                model="claude-sonnet-4-6",
                context_window_chars=200000,
                reserved_output_chars=20000,
                available_input_chars=177000,
                provider_framing_chars=3000,
                system_prompt_chars=13,
                bootstrap_history_chars=13,
                conversation_history_chars=0,
                current_message_chars=0,
                tool_schema_chars=25,
                total_input_chars=3051,
                overflow_chars=0,
                within_budget=True,
                failure_reason=None,
                trimming_applied=False,
                compaction_applied=False,
            ),
        )

    monkeypatch.setattr(
        prompt_context_service.PromptContextService,
        "build_prompts",
        staticmethod(fake_build_prompts),
    )
    monkeypatch.setattr(
        UserSettingsService,
        "get_settings",
        staticmethod(lambda *_args, **_kwargs: settings_record),
    )
    monkeypatch.setattr(
        SettingsService,
        "resolve_enabled_skills",
        staticmethod(lambda _settings_record: ["notes"]),
    )
    monkeypatch.setattr(
        ai_policy.AIPolicyService,
        "resolve_from_settings",
        staticmethod(lambda _settings_record: object()),
    )
    monkeypatch.setattr(
        ai_policy.AIPolicyService,
        "select_provider",
        staticmethod(
            lambda _capability, _policy: type(
                "Selection", (), {"provider": "anthropic"}
            )()
        ),
    )
    monkeypatch.setattr(
        ai_registry,
        "get_default_model",
        lambda *_args, **_kwargs: "claude-sonnet-4-6",
    )
    monkeypatch.setattr(
        request_assembly_service.RequestAssemblyService,
        "build_assembled_inputs",
        staticmethod(fake_build_assembled_inputs),
    )
    monkeypatch.setattr(
        request_assembly_service.RequestAssemblyService,
        "build_prepared_request",
        staticmethod(fake_build_prepared_request),
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
    assert result["data"]["prompt_report"]["system_prompt"]["truncated"] is False
    assert result["data"]["request_budget_report"]["provider"] == "anthropic"
    assert result["data"]["request_budget_report"]["tool_schema_chars"] == 25
    assert result["data"]["workspace_context_menu_actions"] == [
        "copy_markdown",
        "share_text",
        "download",
    ]
    assert captured["db"] == context["db"]
    assert captured["user_id"] == "user-123"
    assert captured["current_weather"] == "sunny"
    assert captured["prepared_request_kwargs"]["allowed_skills"] == ["notes"]


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
