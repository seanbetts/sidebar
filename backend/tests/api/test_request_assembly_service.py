from datetime import UTC, datetime

import pytest

from api.db.base import Base
from api.exceptions import BadRequestError
from api.models.user_settings import UserSettings
from api.services.agent.prompt.composer import PromptContextService
from api.services.agent.request_assembly_service import (
    AssembledChatInputs,
    RequestAssemblyService,
)
from api.services.agent.request_budget_service import PreparedChatRequest
from api.services.capabilities.types import CapabilityLoaderResult


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


def test_normalize_conversation_history_excludes_compacted_source_messages():
    history = RequestAssemblyService.normalize_conversation_history(
        [
            {"id": "bootstrap-1", "role": "user", "content": "I am Sam."},
            {
                "id": "msg-1",
                "role": "user",
                "content": "Old user message",
                "visibility": "hidden",
                "compaction": {"status": "compacted"},
            },
            {
                "id": "summary-1",
                "role": "assistant",
                "content": "Earlier conversation summary",
                "visibility": "hidden",
                "kind": "conversation_compaction_summary",
            },
            {"id": "msg-2", "role": "assistant", "content": "Recent reply"},
        ],
        user_message_id=None,
    )

    assert history == [
        {"role": "user", "content": "I am Sam."},
        {"role": "assistant", "content": "Earlier conversation summary"},
        {"role": "assistant", "content": "Recent reply"},
    ]


def test_normalize_conversation_history_includes_hidden_error_details_for_assistant():
    history = RequestAssemblyService.normalize_conversation_history(
        [
            {
                "id": "assistant-1",
                "role": "assistant",
                "content": "Partial answer",
                "error": "The AI provider is busy right now. Please try again in a moment.",
                "errorDetails": (
                    "{'type': 'error', 'error': {'type': 'overloaded_error', "
                    "'message': 'Overloaded'}, 'request_id': 'req_123'}"
                ),
            }
        ],
        user_message_id=None,
    )

    assert len(history) == 1
    assert history[0]["role"] == "assistant"
    assert "Partial answer" in history[0]["content"]
    assert "Internal diagnostic note for the assistant only" in history[0]["content"]
    assert "The AI provider is busy right now. Please try again in a moment." in history[0]["content"]
    assert "req_123" in history[0]["content"]


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


def test_build_assembled_inputs_replays_persisted_bootstrap_separately():
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
            {
                "id": "bootstrap-1",
                "role": "user",
                "content": "I am Sam.",
                "visibility": "hidden",
                "kind": "conversation_bootstrap",
            },
            {
                "id": "summary-1",
                "role": "assistant",
                "content": "Earlier conversation summary",
                "visibility": "hidden",
                "kind": "conversation_compaction_summary",
            },
            {
                "id": "user-1",
                "role": "user",
                "content": "Earlier",
                "visibility": "hidden",
                "compaction": {"status": "compacted"},
            },
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

    assert assembled.bootstrap_history == [{"role": "user", "content": "I am Sam."}]
    assert assembled.conversation_history == [
        {"role": "assistant", "content": "Earlier conversation summary"},
        {"role": "assistant", "content": "Reply"},
    ]


def test_build_assembled_inputs_passes_blocked_skill_summaries_to_prompt_builder():
    captured: dict[str, object] = {}

    class FakePromptContextService:
        @staticmethod
        def build_prompts(**kwargs):
            captured["blocked_skill_summaries"] = kwargs.get(
                "blocked_skill_summaries"
            )
            return _prompt_bundle(system_prompt="assembled-system")

    blocked_skill_summaries = [
        {
            "skill_id": "google-drive",
            "availability_status": "needs_connection",
            "availability_reason": "missing_connection",
            "availability_remediation": {
                "action": "connect",
                "provider": "google-workspace",
            },
        }
    ]

    RequestAssemblyService.build_assembled_inputs(
        db=object(),
        user_id="user-1",
        message="Connect my Google Drive",
        conversation_id="conversation-1",
        conversation_messages=None,
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
        blocked_skill_summaries=blocked_skill_summaries,
        prompt_context_service=FakePromptContextService,
    )

    assert captured["blocked_skill_summaries"] == blocked_skill_summaries


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


def test_build_assembled_inputs_allows_budget_truncated_system_prompt():
    captured_strict_flags: list[bool] = []

    class FakePromptContextService:
        @staticmethod
        def build_prompts(**kwargs):
            captured_strict_flags.append(kwargs["strict_system_prompt"])
            return _prompt_bundle(
                system_prompt="assembled-system",
                truncated_by_budget=True,
            )

    assembled = RequestAssemblyService.build_assembled_inputs(
        db=object(),
        user_id="user-1",
        message="Current",
        conversation_id="conversation-1",
        conversation_messages=None,
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

    assert assembled.system_prompt == "assembled-system"
    assert assembled.prompt_bundle["report"]["system_prompt"]["truncated_by_budget"] is True
    assert captured_strict_flags == [False]


def test_build_assembled_inputs_retries_metadata_only_attachments_after_budget_truncation():
    captured_flags: list[bool] = []

    class FakePromptContextService:
        @staticmethod
        def build_prompts(**kwargs):
            include_attachment_content = kwargs["include_attachment_content"]
            captured_flags.append(include_attachment_content)
            if include_attachment_content:
                return _prompt_bundle(
                    system_prompt="oversized-with-content",
                    truncated_by_budget=True,
                )
            return _prompt_bundle(system_prompt="metadata-only", truncated_by_budget=False)

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

    assert assembled.system_prompt == "metadata-only"
    assert assembled.prompt_bundle["report"]["system_prompt"]["truncated_by_budget"] is False
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


def test_build_prepared_request_uses_executable_skill_subset_for_tool_resolution():
    captured: dict[str, object] = {}

    def fake_tool_definition_resolver(
        executable_skill_ids: list[str] | None,
    ) -> list[dict[str, object]]:
        captured["executable_skill_ids"] = executable_skill_ids
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
        executable_skill_ids=["notes"],
        tool_definition_resolver=fake_tool_definition_resolver,
    )

    assert captured["executable_skill_ids"] == ["notes"]
    assert prepared.tool_definitions


def test_build_assembled_inputs_passes_loaded_capability_content_to_prompt_builder():
    captured: dict[str, object] = {}

    class FakePromptContextService:
        @staticmethod
        def build_prompts(**kwargs):
            captured["loaded_instructions"] = kwargs.get("loaded_instructions")
            captured["loaded_examples"] = kwargs.get("loaded_examples")
            return _prompt_bundle(system_prompt="assembled-system")

    capability_loader_result = CapabilityLoaderResult(
        selected_skill_ids=("notes",),
        executable_skill_ids=("notes",),
        loaded_instruction_refs=("skills/notes/SKILL.md",),
        loaded_instructions=(
            {
                "skill_id": "notes",
                "ref": "skills/notes/SKILL.md",
                "content": "Use the notes skill for note operations.",
            },
        ),
        loaded_examples=(
            {
                "skill_id": "notes",
                "ref": "skills/notes/examples/basic.md",
                "content": "Example: open yesterday's notes.",
            },
        ),
    )

    RequestAssemblyService.build_assembled_inputs(
        db=object(),
        user_id="user-1",
        message="Open my notes",
        conversation_id="conversation-1",
        conversation_messages=None,
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
        capability_loader_result=capability_loader_result,
        prompt_context_service=FakePromptContextService,
    )

    assert captured["loaded_instructions"] == [
        {
            "skill_id": "notes",
            "ref": "skills/notes/SKILL.md",
            "content": "Use the notes skill for note operations.",
        }
    ]
    assert captured["loaded_examples"] == [
        {
            "skill_id": "notes",
            "ref": "skills/notes/examples/basic.md",
            "content": "Example: open yesterday's notes.",
        }
    ]


def test_prompt_context_service_includes_compact_blocked_skill_guidance_only_when_present(
    test_db,
):
    Base.metadata.create_all(bind=test_db.connection())
    test_db.add(UserSettings(user_id="user-1", name="Sam"))
    test_db.commit()

    prompt_bundle = PromptContextService.build_prompts(
        db=test_db,
        user_id="user-1",
        open_context={},
        attachments=[],
        user_agent=None,
        now=datetime(2026, 3, 7, 12, 0, tzinfo=UTC),
        blocked_skill_summaries=[
            {
                "skill_id": "google-drive",
                "availability_status": "needs_connection",
                "availability_reason": "missing_connection",
                "availability_remediation": {
                    "action": "connect",
                    "provider": "google-workspace",
                },
            }
        ],
    )

    system_prompt = prompt_bundle["system_prompt"]["text"]
    assert "<blocked_capabilities>" in system_prompt
    assert "google-drive" in system_prompt
    assert "connect google-workspace" in system_prompt

    without_blocked = PromptContextService.build_prompts(
        db=test_db,
        user_id="user-1",
        open_context={},
        attachments=[],
        user_agent=None,
        now=datetime(2026, 3, 7, 12, 0, tzinfo=UTC),
        blocked_skill_summaries=[],
    )
    assert "<blocked_capabilities>" not in without_blocked["system_prompt"]["text"]


def test_build_prepared_request_uses_loader_tool_definitions_without_resolver():
    capability_loader_result = CapabilityLoaderResult(
        selected_skill_ids=("notes", "google-drive"),
        executable_skill_ids=("notes",),
        loaded_instruction_refs=("skills/notes/SKILL.md",),
        tool_definitions=(
            {
                "name": "lookup_note",
                "description": "Open a note by ID.",
                "input_schema": {
                    "type": "object",
                    "properties": {"note_id": {"type": "string"}},
                    "required": ["note_id"],
                },
            },
        ),
    )

    def fail_resolver(_allowed_skills):
        raise AssertionError("tool_definition_resolver should not be called")

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
        capability_loader_result=capability_loader_result,
        tool_definition_resolver=fail_resolver,
    )

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
