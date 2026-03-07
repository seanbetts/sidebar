from api.services.agent.request_budget_feedback_service import (
    RequestBudgetFeedbackService,
)
from api.services.agent.request_budget_service import RequestBudgetReport


def _budget_report(
    *,
    system_prompt_chars: int = 10,
    bootstrap_history_chars: int = 5,
    conversation_history_chars: int = 0,
    current_message_chars: int = 8,
    tool_schema_chars: int = 4,
    within_budget: bool = False,
    trimming_applied: bool = False,
    compaction_applied: bool = False,
) -> RequestBudgetReport:
    return RequestBudgetReport(
        provider="anthropic",
        model="claude-sonnet-4-6",
        context_window_chars=100,
        reserved_output_chars=20,
        available_input_chars=70,
        provider_framing_chars=10,
        system_prompt_chars=system_prompt_chars,
        bootstrap_history_chars=bootstrap_history_chars,
        conversation_history_chars=conversation_history_chars,
        current_message_chars=current_message_chars,
        tool_schema_chars=tool_schema_chars,
        total_input_chars=system_prompt_chars
        + bootstrap_history_chars
        + conversation_history_chars
        + current_message_chars
        + tool_schema_chars
        + 10,
        overflow_chars=12,
        within_budget=within_budget,
        failure_reason="request_too_large" if not within_budget else None,
        trimming_applied=trimming_applied,
        compaction_applied=compaction_applied,
    )


def test_dominant_component_prefers_conversation_history_when_largest():
    report = _budget_report(conversation_history_chars=120, current_message_chars=20)

    assert (
        RequestBudgetFeedbackService.dominant_component(report)
        == "conversation_history"
    )


def test_build_overflow_message_uses_history_guidance_for_history_overflow():
    report = _budget_report(conversation_history_chars=120, trimming_applied=True)

    assert RequestBudgetFeedbackService.build_overflow_message(report) == (
        "Chat request is too large even after trimming conversation history. "
        "Start a new conversation or reduce context and try again."
    )


def test_build_overflow_message_uses_context_guidance_for_non_history_overflow():
    report = _budget_report(system_prompt_chars=120, conversation_history_chars=0)

    assert RequestBudgetFeedbackService.build_overflow_message(report) == (
        "Message context is too large for this chat request. Remove some "
        "attachments or close open items and try again."
    )
