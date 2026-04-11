"""Support helpers used by the chat router."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import cast

from fastapi import HTTPException
from sqlalchemy.orm import Session

from api.exceptions import BadRequestError
from api.services.agent.prompt.composer import PromptContextService
from api.services.agent.request_assembly_service import (
    AssembledChatInputs,
    RequestAssemblyService,
)
from api.services.agent.request_budget_service import PreparedChatRequest
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.registry import AIProvider, build_web_search_fallback_summary
from api.services.capabilities.loader import CapabilityLoaderService
from api.services.device_token_service import DeviceTokenService
from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_policy_service import NotificationPolicyService
from api.services.notification_types import (
    NotificationCategory,
    NotificationDeliveryMode,
    NotificationIntent,
)
from api.services.user_settings_service import UserSettingsService

logger = logging.getLogger(__name__)


def build_assistant_reply_notification_body(content: str) -> str | None:
    """Normalize assistant text into a single push-friendly preview string."""
    normalized = " ".join((content or "").split())
    if not normalized:
        return None
    if len(normalized) <= 160:
        return normalized
    return f"{normalized[:157].rstrip()}..."


def deliver_assistant_reply_notification(
    *,
    db: Session,
    user_id: str,
    conversation_id: str,
    assistant_message_id: str,
    assistant_content: str,
    message_visibility: str | None,
    user_settings_service: type[UserSettingsService] = UserSettingsService,
    device_token_service: type[DeviceTokenService] = DeviceTokenService,
    notification_policy_service: type[NotificationPolicyService] = (
        NotificationPolicyService
    ),
    notification_delivery_service: type[NotificationDeliveryService] = (
        NotificationDeliveryService
    ),
) -> None:
    """Best-effort delivery for user-visible assistant replies."""
    if message_visibility == "hidden":
        return

    body = build_assistant_reply_notification_body(assistant_content)
    if not body:
        return

    settings_record = user_settings_service.get_settings(db, user_id)
    device_tokens = device_token_service.list_active_tokens(db, user_id)
    intent = NotificationIntent(
        user_id=user_id,
        category=NotificationCategory.ASSISTANT_REPLY,
        delivery_mode=NotificationDeliveryMode.ALERT,
        title="sideBar replied",
        body=body,
        route=f"sidebar://chat/{conversation_id}",
        metadata={"conversation_id": conversation_id},
    )
    decision = notification_policy_service.evaluate(
        intent,
        settings_record=settings_record,
        device_tokens=device_tokens,
    )
    if not decision.should_deliver:
        return

    try:
        notification_delivery_service.deliver_intent(
            intent,
            device_tokens=decision.matched_tokens,
        )
    except Exception:
        logger.exception(
            "Assistant reply notification delivery failed for conversation %s",
            conversation_id,
            extra={"assistant_message_id": assistant_message_id},
        )


def select_title_messages(messages: list[dict[str, object]]) -> tuple[str, str]:
    """Return the first user/assistant pair suitable for title generation."""
    first_user_message: str | None = None

    for message in messages:
        role = str(message.get("role") or "").strip().lower()
        content = str(message.get("content") or "").strip()
        if not content:
            continue
        if first_user_message is None:
            if role == "user":
                first_user_message = content
            continue
        if role == "assistant":
            return first_user_message, content

    raise BadRequestError("Need a user message and assistant reply to generate title")


def require_completed_soul_calibration(
    onboarding_state: dict[str, object] | None,
) -> None:
    """Block normal AI chat until provider-ready users finish calibration."""
    if not isinstance(onboarding_state, dict):
        return
    if not bool(onboarding_state.get("provider_ready")):
        return
    if bool(onboarding_state.get("is_onboarding_complete")):
        return
    if str(onboarding_state.get("current_onboarding_step") or "") != "soul_calibration":
        return

    raise HTTPException(
        status_code=409,
        detail={
            "error": {
                "code": "ONBOARDING_REQUIRED",
                "message": (
                    "Soul calibration must complete before AI chat is available."
                ),
                "details": {
                    "onboarding_state": onboarding_state,
                },
            }
        },
    )


def assemble_prepared_request(
    *,
    db: Session,
    user_id: str,
    message: str,
    conversation_id: str | None,
    conversation_messages: list[dict[str, object]] | None,
    history: list[dict[str, object]] | None,
    user_message_id: str | None,
    open_context: dict[str, object],
    attachments: list[dict[str, object]],
    user_agent: str | None,
    current_location: str | None,
    current_location_levels: dict[str, object] | str | None,
    current_weather: dict[str, object] | str | None,
    current_timezone: str | None,
    now: datetime,
    onboarding_state: dict[str, object] | None,
    provider: AIProvider,
    model: str,
    selected_skill_ids: list[str] | None,
    executable_skill_ids: list[str] | None,
    blocked_skill_summaries: list[dict[str, object]] | None,
    ai_gateway: AIProviderGateway,
    compaction_applied: bool = False,
) -> tuple[AssembledChatInputs, PreparedChatRequest]:
    """Assemble inputs and attach the prepared-request budget contract."""
    capability_loader_result = CapabilityLoaderService.load_for_turn(
        selected_skill_ids=selected_skill_ids,
        executable_skill_ids=executable_skill_ids,
        tool_definition_resolver=getattr(ai_gateway, "get_chat_tool_definitions", None),
    )
    assembled_inputs = RequestAssemblyService.build_assembled_inputs(
        db=db,
        user_id=user_id,
        message=message,
        conversation_id=conversation_id,
        conversation_messages=conversation_messages,
        request_history=history,
        user_message_id=user_message_id,
        open_context=open_context,
        attachments=attachments,
        user_agent=user_agent,
        current_location=current_location,
        current_location_levels=current_location_levels,
        current_weather=current_weather,
        current_timezone=current_timezone,
        now=now,
        onboarding_state=onboarding_state,
        blocked_skill_summaries=blocked_skill_summaries,
        capability_loader_result=capability_loader_result,
        prompt_context_service=PromptContextService,
    )
    prepared_request = RequestAssemblyService.build_prepared_request(
        provider=provider,
        model=model,
        assembled_inputs=assembled_inputs,
        executable_skill_ids=executable_skill_ids,
        capability_loader_result=capability_loader_result,
        tool_definition_resolver=getattr(
            ai_gateway,
            "get_chat_tool_definitions",
            None,
        ),
        compaction_applied=compaction_applied,
    )
    return assembled_inputs, prepared_request


def apply_chat_model_skill_compatibility(
    *,
    provider: AIProvider,
    model: str,
    executable_skill_ids: list[str],
    blocked_skill_summaries: list[dict[str, object]],
) -> tuple[list[str], list[dict[str, object]]]:
    """Downgrade skills that the selected provider/model cannot execute."""
    adjusted_executable_skill_ids = list(executable_skill_ids)
    adjusted_blocked_skill_summaries = [
        summary
        for summary in blocked_skill_summaries
        if summary.get("skill_id") != "web-search"
    ]
    if "web-search" not in adjusted_executable_skill_ids:
        return adjusted_executable_skill_ids, adjusted_blocked_skill_summaries

    requires_tool_combination = any(
        skill_id != "web-search" for skill_id in adjusted_executable_skill_ids
    )
    fallback_summary = build_web_search_fallback_summary(
        provider,
        model,
        requires_tool_combination=requires_tool_combination,
    )
    if fallback_summary is None:
        return adjusted_executable_skill_ids, adjusted_blocked_skill_summaries

    adjusted_executable_skill_ids = [
        skill_id
        for skill_id in adjusted_executable_skill_ids
        if skill_id != "web-search"
    ]
    adjusted_blocked_skill_summaries.append(cast(dict[str, object], fallback_summary))
    return adjusted_executable_skill_ids, adjusted_blocked_skill_summaries


def build_prompt_preview_payload(
    *,
    assembled_inputs: AssembledChatInputs,
    prepared_request: PreparedChatRequest,
) -> dict[str, object]:
    """Build prompt preview metadata for the tool context."""
    prompt_bundle = assembled_inputs.prompt_bundle
    system_prompt = prompt_bundle.get("system_prompt", {})
    first_message_prompt = prompt_bundle.get("first_message_prompt", {})
    return {
        "system_prompt": system_prompt.get("text", assembled_inputs.system_prompt),
        "first_message_prompt": first_message_prompt.get("text", ""),
        "system_prompt_sections": system_prompt.get("sections", []),
        "first_message_prompt_sections": first_message_prompt.get("sections", []),
        "prompt_report": prompt_bundle.get("report", {}),
        "request_budget_report": prepared_request.budget_report.__dict__,
        "workspace_context_menu_actions": [
            "copy_markdown",
            "share_text",
            "download",
        ],
    }
