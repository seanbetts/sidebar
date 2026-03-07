"""Request budgeting helpers for assembled chat requests."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from api.services.ai.registry import AIProvider


@dataclass(frozen=True)
class ProviderBudgetMetadata:
    """Heuristic provider budget metadata for one prepared request."""

    context_window_chars: int
    reserved_output_chars: int
    provider_framing_chars: int


@dataclass(frozen=True)
class RequestBudgetReport:
    """Structured full-request budget report used for diagnostics and decisions."""

    provider: AIProvider
    model: str
    context_window_chars: int
    reserved_output_chars: int
    available_input_chars: int
    provider_framing_chars: int
    system_prompt_chars: int
    bootstrap_history_chars: int
    conversation_history_chars: int
    current_message_chars: int
    tool_schema_chars: int
    total_input_chars: int
    overflow_chars: int
    within_budget: bool
    failure_reason: str | None
    trimming_applied: bool = False
    compaction_applied: bool = False


@dataclass(frozen=True)
class PreparedChatRequest:
    """Prepared request payload ready for provider-specific translation."""

    provider: AIProvider
    model: str
    system_prompt: str
    bootstrap_history: list[dict[str, Any]]
    conversation_history: list[dict[str, Any]]
    current_user_message: str
    tool_definitions: list[dict[str, Any]]
    budget_report: RequestBudgetReport


class RequestBudgetService:
    """Build conservative budget reports for fully assembled chat requests."""

    _DEFAULT_METADATA: dict[AIProvider, ProviderBudgetMetadata] = {
        # Heuristic defaults only. These are intentionally conservative until
        # provider/model-specific token accounting is added.
        "anthropic": ProviderBudgetMetadata(
            context_window_chars=200_000,
            reserved_output_chars=20_000,
            provider_framing_chars=3_000,
        ),
        "openai": ProviderBudgetMetadata(
            context_window_chars=200_000,
            reserved_output_chars=20_000,
            provider_framing_chars=4_000,
        ),
        "google": ProviderBudgetMetadata(
            context_window_chars=200_000,
            reserved_output_chars=20_000,
            provider_framing_chars=4_000,
        ),
    }

    @classmethod
    def build_prepared_request(
        cls,
        *,
        provider: AIProvider,
        model: str,
        system_prompt: str,
        bootstrap_history: list[dict[str, Any]] | None,
        conversation_history: list[dict[str, Any]] | None,
        current_user_message: str,
        tool_definitions: list[dict[str, Any]] | None,
        metadata: ProviderBudgetMetadata | None = None,
    ) -> PreparedChatRequest:
        """Build a prepared request payload and attach a request budget report."""
        normalized_bootstrap = list(bootstrap_history or [])
        normalized_history = list(conversation_history or [])
        normalized_tools = list(tool_definitions or [])
        report = cls.build_report(
            provider=provider,
            model=model,
            system_prompt=system_prompt,
            bootstrap_history=normalized_bootstrap,
            conversation_history=normalized_history,
            current_user_message=current_user_message,
            tool_definitions=normalized_tools,
            metadata=metadata,
        )
        return PreparedChatRequest(
            provider=provider,
            model=model,
            system_prompt=system_prompt,
            bootstrap_history=normalized_bootstrap,
            conversation_history=normalized_history,
            current_user_message=current_user_message,
            tool_definitions=normalized_tools,
            budget_report=report,
        )

    @classmethod
    def build_report(
        cls,
        *,
        provider: AIProvider,
        model: str,
        system_prompt: str,
        bootstrap_history: list[dict[str, Any]] | None,
        conversation_history: list[dict[str, Any]] | None,
        current_user_message: str,
        tool_definitions: list[dict[str, Any]] | None,
        metadata: ProviderBudgetMetadata | None = None,
        trimming_applied: bool = False,
        compaction_applied: bool = False,
    ) -> RequestBudgetReport:
        """Measure the assembled request and return a structured budget report."""
        resolved_metadata = metadata or cls._DEFAULT_METADATA[provider]
        system_prompt_chars = len(system_prompt or "")
        bootstrap_history_chars = cls._measure_json_chars(bootstrap_history or [])
        conversation_history_chars = cls._measure_json_chars(conversation_history or [])
        current_message_chars = len(current_user_message or "")
        tool_schema_chars = cls._measure_json_chars(
            cls._build_provider_tool_schema_payload(
                provider=provider,
                tool_definitions=tool_definitions or [],
            )
        )
        available_input_chars = max(
            resolved_metadata.context_window_chars
            - resolved_metadata.reserved_output_chars
            - resolved_metadata.provider_framing_chars,
            0,
        )
        total_input_chars = (
            system_prompt_chars
            + bootstrap_history_chars
            + conversation_history_chars
            + current_message_chars
            + tool_schema_chars
            + resolved_metadata.provider_framing_chars
        )
        overflow_chars = max(total_input_chars - available_input_chars, 0)
        within_budget = overflow_chars == 0
        failure_reason = None if within_budget else "request_too_large"

        return RequestBudgetReport(
            provider=provider,
            model=model,
            context_window_chars=resolved_metadata.context_window_chars,
            reserved_output_chars=resolved_metadata.reserved_output_chars,
            available_input_chars=available_input_chars,
            provider_framing_chars=resolved_metadata.provider_framing_chars,
            system_prompt_chars=system_prompt_chars,
            bootstrap_history_chars=bootstrap_history_chars,
            conversation_history_chars=conversation_history_chars,
            current_message_chars=current_message_chars,
            tool_schema_chars=tool_schema_chars,
            total_input_chars=total_input_chars,
            overflow_chars=overflow_chars,
            within_budget=within_budget,
            failure_reason=failure_reason,
            trimming_applied=trimming_applied,
            compaction_applied=compaction_applied,
        )

    @staticmethod
    def _measure_json_chars(payload: Any) -> int:
        """Measure serialized chars for structured request payload components."""
        return len(json.dumps(payload, sort_keys=True))

    @classmethod
    def _build_provider_tool_schema_payload(
        cls,
        *,
        provider: AIProvider,
        tool_definitions: list[dict[str, Any]],
    ) -> Any:
        """Build the provider-shaped tool schema payload used for budgeting."""
        if provider == "openai":
            return [
                {
                    "type": "function",
                    "function": {
                        "name": tool["name"],
                        "description": tool["description"],
                        "parameters": tool["input_schema"],
                    },
                }
                for tool in tool_definitions
            ]
        if provider == "google":
            return [
                {
                    "function_declarations": [
                        {
                            "name": tool["name"],
                            "description": tool["description"],
                            "parameters": cls._normalize_google_schema(
                                tool.get("input_schema", {})
                            ),
                        }
                        for tool in tool_definitions
                    ]
                }
            ]
        return tool_definitions

    @classmethod
    def _normalize_google_schema(cls, value: Any) -> Any:
        """Normalize JSON schema to the Google tool declaration shape."""
        if isinstance(value, dict):
            normalized: dict[str, Any] = {}
            nullable = False
            schema_type = value.get("type")
            if isinstance(schema_type, list):
                type_options = [
                    option.lower() for option in schema_type if isinstance(option, str)
                ]
                non_null_options = [
                    option for option in type_options if option != "null"
                ]
                nullable = "null" in type_options
                if non_null_options:
                    normalized["type"] = non_null_options[0]
            for key, entry in value.items():
                if key == "type":
                    if "type" not in normalized and isinstance(entry, str):
                        normalized["type"] = entry.lower()
                    continue
                normalized[key] = cls._normalize_google_schema(entry)
            if nullable:
                normalized["nullable"] = True
            return normalized
        if isinstance(value, list):
            return [cls._normalize_google_schema(item) for item in value]
        return value
