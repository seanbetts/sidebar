"""Feedback helpers for chat request budget decisions."""

from __future__ import annotations

import logging

from api.metrics import chat_request_budget_events_total
from api.services.agent.request_budget_service import RequestBudgetReport

logger = logging.getLogger(__name__)

_CONTEXT_TOO_LARGE_MESSAGE = (
    "Message context is too large for this chat request. Remove some attachments "
    "or close open items and try again."
)
_HISTORY_TOO_LARGE_MESSAGE = (
    "Chat request is too large even after trimming conversation history. Start a "
    "new conversation or reduce context and try again."
)


class RequestBudgetFeedbackService:
    """Classify budget outcomes into user-facing and operational feedback."""

    @staticmethod
    def dominant_component(report: RequestBudgetReport) -> str:
        """Return the largest request component for diagnostics and errors."""
        component_sizes = {
            "system_prompt": report.system_prompt_chars,
            "bootstrap_history": report.bootstrap_history_chars,
            "conversation_history": report.conversation_history_chars,
            "current_message": report.current_message_chars,
            "tool_schema": report.tool_schema_chars,
        }
        return max(component_sizes.items(), key=lambda item: item[1])[0]

    @classmethod
    def build_overflow_message(cls, report: RequestBudgetReport) -> str:
        """Return the user-facing overflow message for the dominant cause."""
        if cls.dominant_component(report) == "conversation_history":
            return _HISTORY_TOO_LARGE_MESSAGE
        return _CONTEXT_TOO_LARGE_MESSAGE

    @classmethod
    def log_budget_decision(
        cls,
        *,
        stage: str,
        report: RequestBudgetReport,
        conversation_id: str | None,
        trimmed_history_count: int = 0,
    ) -> None:
        """Emit a metric and structured log for notable budget decisions."""
        if (
            report.within_budget
            and not report.trimming_applied
            and not report.compaction_applied
        ):
            return

        dominant_component = cls.dominant_component(report)
        outcome = "overflow" if not report.within_budget else "within_budget"
        chat_request_budget_events_total.labels(
            stage=stage,
            outcome=outcome,
            dominant_component=dominant_component,
        ).inc()

        log_method = logger.warning if outcome == "overflow" else logger.info
        log_method(
            (
                "Chat request budget decision "
                "(stage=%s outcome=%s provider=%s model=%s "
                "dominant_component=%s overflow_chars=%s trimming_applied=%s "
                "compaction_applied=%s trimmed_history_count=%s "
                "system_prompt_chars=%s bootstrap_history_chars=%s "
                "conversation_history_chars=%s current_message_chars=%s "
                "tool_schema_chars=%s conversation_id=%s)"
            ),
            stage,
            outcome,
            report.provider,
            report.model,
            dominant_component,
            report.overflow_chars,
            report.trimming_applied,
            report.compaction_applied,
            trimmed_history_count,
            report.system_prompt_chars,
            report.bootstrap_history_chars,
            report.conversation_history_chars,
            report.current_message_chars,
            report.tool_schema_chars,
            conversation_id or "none",
        )
