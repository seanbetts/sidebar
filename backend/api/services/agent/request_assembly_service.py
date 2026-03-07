"""Service-layer helpers for assembling chat inputs before provider execution."""

from __future__ import annotations

import logging
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
        prompt_context_service: type[PromptContextService] = PromptContextService,
    ) -> AssembledChatInputs:
        """Assemble normalized history plus the current prompt bundle."""
        history = list(request_history or [])
        if conversation_messages is not None:
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
                strict_system_prompt=True,
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

        prompt_report = prompt_bundle["report"]
        if prompt_report["system_prompt"]["truncated_by_budget"]:
            logger.warning(
                (
                    "System prompt exceeded configured maximum size "
                    "(attachments=%s conversation_id=%s)"
                ),
                len(attachments),
                conversation_id or "none",
            )
            raise BadRequestError(_OVERSIZE_CONTEXT_MESSAGE)

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
        tool_definitions: list[dict[str, Any]] | None = None,
    ) -> PreparedChatRequest:
        """Wrap assembled chat inputs in the prepared-request budget contract."""
        return RequestBudgetService.build_prepared_request(
            provider=provider,
            model=model,
            system_prompt=assembled_inputs.system_prompt,
            bootstrap_history=assembled_inputs.bootstrap_history,
            conversation_history=assembled_inputs.conversation_history,
            current_user_message=assembled_inputs.current_user_message,
            tool_definitions=tool_definitions or [],
        )
