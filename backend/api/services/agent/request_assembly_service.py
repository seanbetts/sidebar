"""Service-layer helpers for assembling chat inputs before provider execution."""

from __future__ import annotations

import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy.orm import Session

from api.exceptions import BadRequestError
from api.services.agent.prompt.composer import PromptBuildResult, PromptContextService
from api.services.agent.request_budget_service import (
    PreparedChatRequest,
    RequestBudgetService,
)
from api.services.ai.registry import AIProvider
from api.services.capabilities.types import CapabilityLoaderResult

logger = logging.getLogger(__name__)

_OVERSIZE_CONTEXT_MESSAGE = (
    "Message context is too large. Remove some attachments or close open items "
    "and try again."
)


@dataclass(frozen=True)
class AssembledChatInputs:
    """Normalized per-turn chat inputs assembled before provider translation."""

    system_prompt: str
    bootstrap_history: list[dict[str, Any]]
    conversation_history: list[dict[str, Any]]
    current_user_message: str
    prompt_bundle: PromptBuildResult


class RequestAssemblyService:
    """Assemble chat inputs behind a service-layer boundary."""

    @staticmethod
    def is_bootstrap_message(message: dict[str, Any]) -> bool:
        """Return whether a stored transcript entry is persisted bootstrap."""
        return message.get("kind") == "conversation_bootstrap"

    @staticmethod
    def is_compacted_source_message(message: dict[str, Any]) -> bool:
        """Return whether a stored transcript entry was compacted out of replay."""
        compaction = message.get("compaction")
        return isinstance(compaction, dict) and compaction.get("status") == "compacted"

    @classmethod
    def extract_persisted_bootstrap_history(
        cls,
        messages: list[dict[str, Any]] | None,
    ) -> list[dict[str, Any]]:
        """Extract persisted bootstrap messages into replay history shape."""
        bootstrap_history: list[dict[str, Any]] = []
        for message in messages or []:
            if not cls.is_bootstrap_message(message):
                continue
            role = message.get("role")
            content = message.get("content")
            if role not in {"user", "assistant"} or content is None:
                continue
            bootstrap_history.append({"role": role, "content": content})
        return bootstrap_history

    @staticmethod
    def build_bootstrap_history(
        *,
        history: list[dict[str, Any]],
        prompt_bundle: PromptBuildResult,
    ) -> list[dict[str, Any]]:
        """Build first-turn bootstrap history when no transcript exists yet."""
        if history:
            return []

        bootstrap_text = prompt_bundle["first_message_prompt"]["text"].strip()
        if not bootstrap_text:
            return []

        return [{"role": "user", "content": bootstrap_text}]

    @staticmethod
    def build_persisted_bootstrap_message(
        *,
        bootstrap_history: list[dict[str, Any]],
        timestamp: str,
        message_id: str,
    ) -> dict[str, Any] | None:
        """Build the hidden persisted transcript entry for bootstrap history."""
        if not bootstrap_history:
            return None

        bootstrap_message = bootstrap_history[0]
        return {
            "id": message_id,
            "role": bootstrap_message["role"],
            "content": bootstrap_message["content"],
            "status": "complete",
            "timestamp": timestamp,
            "visibility": "hidden",
            "kind": "conversation_bootstrap",
        }

    @staticmethod
    def normalize_conversation_history(
        messages: list[dict[str, Any]] | None,
        user_message_id: str | None,
    ) -> list[dict[str, Any]]:
        """Normalize stored transcript messages into model-ready chat history."""
        history: list[dict[str, Any]] = []
        if not messages:
            return history

        for message in messages:
            if RequestAssemblyService.is_bootstrap_message(message):
                continue
            if RequestAssemblyService.is_compacted_source_message(message):
                continue

            role = message.get("role")
            if role not in {"user", "assistant"}:
                continue

            content = message.get("content")
            if content is None:
                continue

            if user_message_id and message.get("id") == user_message_id:
                continue

            history.append({"role": role, "content": content})

        return history

    @classmethod
    def build_assembled_inputs(
        cls,
        *,
        db: Session,
        user_id: str,
        message: str,
        conversation_id: str | None,
        conversation_messages: list[dict[str, Any]] | None,
        request_history: list[dict[str, Any]] | None,
        user_message_id: str | None,
        open_context: dict[str, Any],
        attachments: list[dict[str, Any]],
        user_agent: str | None,
        current_location: str | None,
        current_location_levels: dict[str, Any] | str | None,
        current_weather: dict[str, Any] | str | None,
        current_timezone: str | None,
        now: datetime,
        blocked_skill_summaries: list[dict[str, Any]] | None = None,
        capability_loader_result: CapabilityLoaderResult | None = None,
        prompt_context_service: type[PromptContextService] = PromptContextService,
    ) -> AssembledChatInputs:
        """Assemble normalized history plus the current prompt bundle."""
        history = list(request_history or [])
        persisted_bootstrap_history: list[dict[str, Any]] = []
        if conversation_messages is not None:
            persisted_bootstrap_history = cls.extract_persisted_bootstrap_history(
                conversation_messages
            )
            history = cls.normalize_conversation_history(
                conversation_messages,
                user_message_id,
            )

        def _build_prompt_bundle(
            *,
            include_attachment_content: bool,
        ) -> PromptBuildResult:
            return prompt_context_service.build_prompts(
                db=db,
                user_id=user_id,
                open_context=open_context,
                attachments=attachments,
                user_agent=user_agent,
                current_location=current_location,
                current_location_levels=current_location_levels,
                current_weather=current_weather,
                current_timezone=current_timezone,
                now=now,
                blocked_skill_summaries=blocked_skill_summaries,
                loaded_instructions=list(
                    (
                        capability_loader_result or CapabilityLoaderResult()
                    ).loaded_instructions
                ),
                loaded_examples=list(
                    (
                        capability_loader_result or CapabilityLoaderResult()
                    ).loaded_examples
                ),
                strict_system_prompt=False,
                include_attachment_content=include_attachment_content,
            )

        try:
            prompt_bundle = _build_prompt_bundle(include_attachment_content=True)
        except ValueError as error:
            if attachments:
                logger.warning(
                    (
                        "Prompt build rejected with attachment content; "
                        "retrying metadata-only attachments: %s "
                        "(attachments=%s conversation_id=%s)"
                    ),
                    str(error),
                    len(attachments),
                    conversation_id or "none",
                )
                try:
                    prompt_bundle = _build_prompt_bundle(
                        include_attachment_content=False
                    )
                except ValueError as retry_error:
                    logger.warning(
                        (
                            "Prompt build still rejected after attachment-content "
                            "fallback: %s (attachments=%s conversation_id=%s)"
                        ),
                        str(retry_error),
                        len(attachments),
                        conversation_id or "none",
                    )
                    raise BadRequestError(_OVERSIZE_CONTEXT_MESSAGE) from retry_error
            else:
                logger.warning(
                    (
                        "Prompt build rejected chat request: %s "
                        "(attachments=%s conversation_id=%s)"
                    ),
                    str(error),
                    len(attachments),
                    conversation_id or "none",
                )
                raise BadRequestError(str(error)) from error

        if (
            attachments
            and prompt_bundle["report"]["system_prompt"]["truncated_by_budget"]
        ):
            logger.warning(
                (
                    "Prompt bundle exceeded prompt-only size budget with attachment "
                    "content; retrying metadata-only attachments "
                    "(attachments=%s conversation_id=%s)"
                ),
                len(attachments),
                conversation_id or "none",
            )
            try:
                prompt_bundle = _build_prompt_bundle(include_attachment_content=False)
            except ValueError as retry_error:
                logger.warning(
                    (
                        "Prompt build rejected during attachment metadata-only retry: "
                        "%s (attachments=%s conversation_id=%s)"
                    ),
                    str(retry_error),
                    len(attachments),
                    conversation_id or "none",
                )
                raise BadRequestError(_OVERSIZE_CONTEXT_MESSAGE) from retry_error

        if prompt_bundle["report"]["system_prompt"]["truncated_by_budget"]:
            logger.warning(
                (
                    "System prompt exceeded configured prompt-only size budget; "
                    "continuing with full-request budgeting "
                    "(attachments=%s conversation_id=%s)"
                ),
                len(attachments),
                conversation_id or "none",
            )

        bootstrap_history = list(persisted_bootstrap_history)
        if not bootstrap_history:
            bootstrap_history = cls.build_bootstrap_history(
                history=history,
                prompt_bundle=prompt_bundle,
            )
        return AssembledChatInputs(
            system_prompt=prompt_bundle["system_prompt"]["text"],
            bootstrap_history=bootstrap_history,
            conversation_history=history,
            current_user_message=message,
            prompt_bundle=prompt_bundle,
        )

    @staticmethod
    def build_prepared_request(
        *,
        provider: AIProvider,
        model: str,
        assembled_inputs: AssembledChatInputs,
        allowed_skills: list[str] | None = None,
        executable_skill_ids: list[str] | None = None,
        capability_loader_result: CapabilityLoaderResult | None = None,
        tool_definition_resolver: (
            Callable[[list[str] | None], list[dict[str, Any]]] | None
        ) = None,
        tool_definitions: list[dict[str, Any]] | None = None,
        compaction_applied: bool = False,
    ) -> PreparedChatRequest:
        """Wrap assembled chat inputs in the prepared-request budget contract."""
        resolved_tool_definitions = list(tool_definitions or [])
        if not resolved_tool_definitions and capability_loader_result is not None:
            resolved_tool_definitions = list(capability_loader_result.tool_definitions)
        if not resolved_tool_definitions and tool_definition_resolver is not None:
            resolved_tool_definitions = tool_definition_resolver(
                executable_skill_ids
                if executable_skill_ids is not None
                else allowed_skills
            )

        return RequestBudgetService.build_prepared_request(
            provider=provider,
            model=model,
            system_prompt=assembled_inputs.system_prompt,
            bootstrap_history=assembled_inputs.bootstrap_history,
            conversation_history=assembled_inputs.conversation_history,
            current_user_message=assembled_inputs.current_user_message,
            tool_definitions=resolved_tool_definitions,
            compaction_applied=compaction_applied,
        )
