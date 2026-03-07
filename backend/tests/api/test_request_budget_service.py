import json

from api.services.agent.request_budget_service import (
    PreparedChatRequest,
    ProviderBudgetMetadata,
    RequestBudgetService,
)


def test_build_report_measures_request_components_separately():
    tool_definitions = [
        {
            "name": "lookup_note",
            "description": "Open a note by ID.",
            "input_schema": {
                "type": "object",
                "properties": {"note_id": {"type": "string"}},
                "required": ["note_id"],
            },
        }
    ]
    metadata = ProviderBudgetMetadata(
        context_window_chars=1000,
        reserved_output_chars=120,
        provider_framing_chars=30,
    )

    report = RequestBudgetService.build_report(
        provider="anthropic",
        model="claude-sonnet-4-6",
        system_prompt="System rules",
        bootstrap_history=[{"role": "user", "content": "I am Sam."}],
        conversation_history=[{"role": "assistant", "content": "How can I help?"}],
        current_user_message="Summarise the document.",
        tool_definitions=tool_definitions,
        metadata=metadata,
    )

    assert report.provider == "anthropic"
    assert report.model == "claude-sonnet-4-6"
    assert report.system_prompt_chars == len("System rules")
    assert report.bootstrap_history_chars == len(
        json.dumps([{"role": "user", "content": "I am Sam."}], sort_keys=True)
    )
    assert report.conversation_history_chars == len(
        json.dumps(
            [{"role": "assistant", "content": "How can I help?"}],
            sort_keys=True,
        )
    )
    assert report.current_message_chars == len("Summarise the document.")
    assert report.tool_schema_chars == len(json.dumps(tool_definitions, sort_keys=True))
    assert report.available_input_chars == 850
    assert report.total_input_chars == (
        report.system_prompt_chars
        + report.bootstrap_history_chars
        + report.conversation_history_chars
        + report.current_message_chars
        + report.tool_schema_chars
        + report.provider_framing_chars
    )
    assert report.within_budget is True
    assert report.overflow_chars == 0
    assert report.failure_reason is None


def test_build_report_flags_overflow_with_reason():
    metadata = ProviderBudgetMetadata(
        context_window_chars=120,
        reserved_output_chars=20,
        provider_framing_chars=10,
    )

    report = RequestBudgetService.build_report(
        provider="openai",
        model="gpt-5.2",
        system_prompt="x" * 50,
        bootstrap_history=[{"role": "user", "content": "y" * 30}],
        conversation_history=[{"role": "assistant", "content": "z" * 30}],
        current_user_message="w" * 30,
        tool_definitions=[],
        metadata=metadata,
    )

    assert report.available_input_chars == 90
    assert report.total_input_chars > report.available_input_chars
    assert report.within_budget is False
    assert report.overflow_chars == report.total_input_chars - report.available_input_chars
    assert report.failure_reason == "request_too_large"


def test_build_prepared_request_attaches_budget_report():
    prepared = RequestBudgetService.build_prepared_request(
        provider="google",
        model="gemini-3.1-pro-preview",
        system_prompt="System rules",
        bootstrap_history=[{"role": "user", "content": "I am Sam."}],
        conversation_history=[],
        current_user_message="Hello",
        tool_definitions=[],
        metadata=ProviderBudgetMetadata(
            context_window_chars=500,
            reserved_output_chars=100,
            provider_framing_chars=20,
        ),
    )

    assert isinstance(prepared, PreparedChatRequest)
    assert prepared.provider == "google"
    assert prepared.model == "gemini-3.1-pro-preview"
    assert prepared.system_prompt == "System rules"
    assert prepared.bootstrap_history == [{"role": "user", "content": "I am Sam."}]
    assert prepared.conversation_history == []
    assert prepared.current_user_message == "Hello"
    assert prepared.tool_definitions == []
    assert prepared.budget_report.provider == "google"


def test_build_report_measures_provider_specific_openai_tool_schema():
    tool_definitions = [
        {
            "name": "lookup_note",
            "description": "Open a note by ID.",
            "input_schema": {
                "type": "object",
                "properties": {"note_id": {"type": "string"}},
                "required": ["note_id"],
            },
        }
    ]

    report = RequestBudgetService.build_report(
        provider="openai",
        model="gpt-5.2",
        system_prompt="System rules",
        bootstrap_history=[],
        conversation_history=[],
        current_user_message="Hello",
        tool_definitions=tool_definitions,
        metadata=ProviderBudgetMetadata(
            context_window_chars=1000,
            reserved_output_chars=120,
            provider_framing_chars=30,
        ),
    )

    assert report.tool_schema_chars == len(
        json.dumps(
            [
                {
                    "type": "function",
                    "function": {
                        "name": "lookup_note",
                        "description": "Open a note by ID.",
                        "parameters": {
                            "type": "object",
                            "properties": {"note_id": {"type": "string"}},
                            "required": ["note_id"],
                        },
                    },
                }
            ],
            sort_keys=True,
        )
    )


def test_build_report_measures_provider_specific_google_tool_schema():
    tool_definitions = [
        {
            "name": "lookup_note",
            "description": "Open a note by ID.",
            "input_schema": {
                "type": ["OBJECT", "null"],
                "properties": {"note_id": {"type": "STRING"}},
                "required": ["note_id"],
            },
        }
    ]

    report = RequestBudgetService.build_report(
        provider="google",
        model="gemini-3.1-pro-preview",
        system_prompt="System rules",
        bootstrap_history=[],
        conversation_history=[],
        current_user_message="Hello",
        tool_definitions=tool_definitions,
        metadata=ProviderBudgetMetadata(
            context_window_chars=1000,
            reserved_output_chars=120,
            provider_framing_chars=30,
        ),
    )

    assert report.tool_schema_chars == len(
        json.dumps(
            [
                {
                    "function_declarations": [
                        {
                            "name": "lookup_note",
                            "description": "Open a note by ID.",
                            "parameters": {
                                "type": "object",
                                "properties": {
                                    "note_id": {"type": "string"},
                                },
                                "required": ["note_id"],
                                "nullable": True,
                            },
                        }
                    ]
                }
            ],
            sort_keys=True,
        )
    )


def test_build_prepared_request_trims_oldest_history_until_within_budget():
    prepared = RequestBudgetService.build_prepared_request(
        provider="anthropic",
        model="claude-sonnet-4-6",
        system_prompt="",
        bootstrap_history=[],
        conversation_history=[
            {"role": "user", "content": "a" * 10},
            {"role": "assistant", "content": "b" * 10},
            {"role": "user", "content": "c" * 10},
        ],
        current_user_message="",
        tool_definitions=[],
        metadata=ProviderBudgetMetadata(
            context_window_chars=120,
            reserved_output_chars=20,
            provider_framing_chars=10,
        ),
    )

    assert prepared.conversation_history == [
        {"role": "user", "content": "c" * 10},
    ]
    assert prepared.budget_report.trimming_applied is True
    assert prepared.budget_report.within_budget is True


def test_build_prepared_request_preserves_overflow_when_fixed_costs_exceed_budget():
    prepared = RequestBudgetService.build_prepared_request(
        provider="anthropic",
        model="claude-sonnet-4-6",
        system_prompt="x" * 200,
        bootstrap_history=[],
        conversation_history=[{"role": "user", "content": "a" * 10}],
        current_user_message="",
        tool_definitions=[],
        metadata=ProviderBudgetMetadata(
            context_window_chars=120,
            reserved_output_chars=20,
            provider_framing_chars=10,
        ),
    )

    assert prepared.conversation_history == []
    assert prepared.budget_report.trimming_applied is True
    assert prepared.budget_report.within_budget is False
    assert prepared.budget_report.failure_reason == "request_too_large"
