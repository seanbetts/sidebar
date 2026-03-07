from datetime import UTC, datetime

import pytest

from api.exceptions import BadRequestError
from api.services.agent.request_assembly_service import (
    AssembledChatInputs,
    RequestAssemblyService,
)
from api.services.agent.request_budget_service import PreparedChatRequest


def _prompt_bundle(*, system_prompt: str = "system", truncated_by_budget: bool = False):
    return {
        "system_prompt": {
            "text": system_prompt,
            "truncated_by_budget": truncated_by_budget,
        },
        "first_message_prompt": {"text": "first"},
        "report": {
            "system_prompt": {
                "truncated_by_budget": truncated_by_budget,
            }
        },
    }


def test_normalize_conversation_history_filters_and_excludes_current_message():
    history = RequestAssemblyService.normalize_conversation_history(
        [
            {"id": "user-1", "role": "user", "content": "Hello"},
            {"id": "assistant-1", "role": "assistant", "content": "Hi"},
            {"id": "system-1", "role": "system", "content": "skip"},
            {"id": "tool-1", "role": "assistant", "content": None},
            {"id": "user-2", "role": "user", "content": "Current"},
        ],
        user_message_id="user-2",
    )

    assert history == [
        {"role": "user", "content": "Hello"},
        {"role": "assistant", "content": "Hi"},
    ]


def test_build_assembled_inputs_uses_conversation_messages_over_request_history():
    class FakePromptContextService:
        @staticmethod
        def build_prompts(**_kwargs):
            return _prompt_bundle(system_prompt="assembled-system")

    assembled = RequestAssemblyService.build_assembled_inputs(
        db=object(),
        user_id="user-1",
        message="Current",
        conversation_id="conversation-1",
        conversation_messages=[
            {"id": "user-1", "role": "user", "content": "Earlier"},
            {"id": "assistant-1", "role": "assistant", "content": "Reply"},
            {"id": "user-2", "role": "user", "content": "Current"},
        ],
        request_history=[{"role": "assistant", "content": "stale"}],
        user_message_id="user-2",
        open_context={},
        attachments=[],
        user_agent=None,
        current_location=None,
        current_location_levels=None,
        current_weather=None,
        current_timezone=None,
        now=datetime.now(UTC),
        prompt_context_service=FakePromptContextService,
    )

    assert isinstance(assembled, AssembledChatInputs)
    assert assembled.system_prompt == "assembled-system"
    assert assembled.conversation_history == [
        {"role": "user", "content": "Earlier"},
        {"role": "assistant", "content": "Reply"},
    ]
    assert assembled.current_user_message == "Current"


def test_build_assembled_inputs_retries_without_attachment_content():
    captured_flags: list[bool] = []

    class FakePromptContextService:
        @staticmethod
        def build_prompts(**kwargs):
            include_attachment_content = kwargs["include_attachment_content"]
            captured_flags.append(include_attachment_content)
            if include_attachment_content:
                raise ValueError("prompt too large")
            return _prompt_bundle(system_prompt="fallback-system")

    assembled = RequestAssemblyService.build_assembled_inputs(
        db=object(),
        user_id="user-1",
        message="Current",
        conversation_id="conversation-1",
        conversation_messages=None,
        request_history=[],
        user_message_id=None,
        open_context={},
        attachments=[{"file_id": "1", "filename": "doc.md"}],
        user_agent=None,
        current_location=None,
        current_location_levels=None,
        current_weather=None,
        current_timezone=None,
        now=datetime.now(UTC),
        prompt_context_service=FakePromptContextService,
    )

    assert assembled.system_prompt == "fallback-system"
    assert captured_flags == [True, False]


def test_build_assembled_inputs_injects_bootstrap_history_on_first_turn():
    class FakePromptContextService:
        @staticmethod
        def build_prompts(**_kwargs):
            return _prompt_bundle(system_prompt="system", truncated_by_budget=False)

    assembled = RequestAssemblyService.build_assembled_inputs(
        db=object(),
        user_id="user-1",
        message="Current",
        conversation_id="conversation-1",
        conversation_messages=[],
        request_history=[],
        user_message_id=None,
        open_context={},
        attachments=[],
        user_agent=None,
        current_location=None,
        current_location_levels=None,
        current_weather=None,
        current_timezone=None,
        now=datetime.now(UTC),
        prompt_context_service=FakePromptContextService,
    )

    assert assembled.bootstrap_history == [{"role": "user", "content": "first"}]
    assert assembled.conversation_history == []


def test_build_assembled_inputs_raises_clear_error_after_attachment_fallback_fails():
    class FakePromptContextService:
        @staticmethod
        def build_prompts(**_kwargs):
            raise ValueError("prompt too large")

    with pytest.raises(BadRequestError) as exc_info:
        RequestAssemblyService.build_assembled_inputs(
            db=object(),
            user_id="user-1",
            message="Current",
            conversation_id="conversation-1",
            conversation_messages=None,
            request_history=[],
            user_message_id=None,
            open_context={},
            attachments=[{"file_id": "1", "filename": "doc.md"}],
            user_agent=None,
            current_location=None,
            current_location_levels=None,
            current_weather=None,
            current_timezone=None,
            now=datetime.now(UTC),
            prompt_context_service=FakePromptContextService,
        )

    assert str(exc_info.value) == (
        "Message context is too large. Remove some attachments or close open items and try again."
    )


def test_build_prepared_request_wraps_assembled_inputs():
    prepared = RequestAssemblyService.build_prepared_request(
        provider="anthropic",
        model="claude-sonnet-4-6",
        assembled_inputs=AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[{"role": "user", "content": "first"}],
            conversation_history=[{"role": "assistant", "content": "Earlier"}],
            current_user_message="Current",
            prompt_bundle=_prompt_bundle(system_prompt="system"),
        ),
    )

    assert isinstance(prepared, PreparedChatRequest)
    assert prepared.provider == "anthropic"
    assert prepared.model == "claude-sonnet-4-6"
    assert prepared.system_prompt == "system"
    assert prepared.bootstrap_history == [{"role": "user", "content": "first"}]
    assert prepared.conversation_history == [
        {"role": "assistant", "content": "Earlier"}
    ]
    assert prepared.current_user_message == "Current"


def test_build_prepared_request_resolves_tool_definitions_from_resolver():
    captured: dict[str, object] = {}

    def fake_tool_definition_resolver(
        allowed_skills: list[str] | None,
    ) -> list[dict[str, object]]:
        captured["allowed_skills"] = allowed_skills
        return [
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

    prepared = RequestAssemblyService.build_prepared_request(
        provider="anthropic",
        model="claude-sonnet-4-6",
        assembled_inputs=AssembledChatInputs(
            system_prompt="system",
            bootstrap_history=[{"role": "user", "content": "first"}],
            conversation_history=[{"role": "assistant", "content": "Earlier"}],
            current_user_message="Current",
            prompt_bundle=_prompt_bundle(system_prompt="system"),
        ),
        allowed_skills=["notes"],
        tool_definition_resolver=fake_tool_definition_resolver,
    )

    assert captured["allowed_skills"] == ["notes"]
    assert prepared.tool_definitions == [
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
    assert prepared.budget_report.tool_schema_chars > 0
