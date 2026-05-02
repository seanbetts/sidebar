"""Chat router with SSE streaming support."""
# ruff: noqa: B008

import hashlib
import json
import logging
import time
from datetime import UTC, datetime
from typing import TypedDict, cast
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
from google import genai
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.config import settings
from api.constants import ChatConstants
from api.db.dependencies import get_current_user_id
from api.db.session import get_db, user_scoped_session
from api.exceptions import BadRequestError
from api.metrics import (
    chat_messages_total,
    chat_stream_errors_total,
    chat_streaming_duration_seconds,
)
from api.middleware import rate_limit as rate_limit_module
from api.schemas.tool_context import ToolExecutionContext
from api.services.agent.conversation_compaction_service import (
    ConversationCompactionService,
)
from api.services.agent.orchestrator.event_emitter import (
    ONBOARDING_STREAM_EVENT_TYPES,
)
from api.services.agent.prompt.composer import PromptContextService
from api.services.agent.request_assembly_service import RequestAssemblyService
from api.services.agent.request_budget_feedback_service import (
    RequestBudgetFeedbackService,
)
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.ai.chat_stream_error_contract import build_chat_stream_error_event
from api.services.ai.chat_stream_sync_protocol import CUSTOM_CHAT_STREAM_EVENT_TYPES
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.registry import VALID_AI_PROVIDERS, AIProvider
from api.services.capabilities.loader import CapabilityLoaderService
from api.services.capabilities.resolver import CapabilityResolverService
from api.services.capabilities.runtime_state import RuntimeCapabilityService
from api.services.chat_router_support import (
    apply_chat_model_skill_compatibility,
    assemble_prepared_request,
    build_prompt_preview_payload,
    deliver_assistant_reply_notification,
    require_completed_soul_calibration,
    select_title_messages,
)
from api.services.conversation_service import ConversationService
from api.services.device_token_service import DeviceTokenService
from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_policy_service import NotificationPolicyService
from api.services.onboarding_service import OnboardingService
from api.services.settings_service import SettingsService
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.user_settings_service import UserSettingsService
from api.utils.validation import parse_uuid

router = APIRouter(prefix="/chat", tags=["chat"])
logger = logging.getLogger(__name__)

TITLE_CACHE_TTL_SECONDS = ChatConstants.TITLE_CACHE_TTL_SECONDS
TITLE_CACHE_MAX_ENTRIES = ChatConstants.TITLE_CACHE_MAX_ENTRIES


class _TitleCacheEntry(TypedDict):
    title: str
    timestamp: float


TITLE_CACHE: dict[str, _TitleCacheEntry] = {}


def _trimmed_string(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    trimmed = value.strip()
    return trimmed or None


def _persist_terminal_stream_error(
    *,
    user_id: str,
    conversation_uuid: UUID | None,
    message: str,
    user_message_id: str | None,
    assistant_message_id: str | None,
    message_visibility: str | None,
    assistant_content: str,
    tool_calls: list[dict] | None,
    error_event: dict,
) -> None:
    if conversation_uuid is None:
        return

    persisted_user_message_id = _trimmed_string(user_message_id) or str(uuid4())
    persisted_assistant_message_id = _trimmed_string(assistant_message_id) or str(
        uuid4()
    )
    timestamp = datetime.now(UTC).isoformat()
    explanation = _trimmed_string(error_event.get("assistant_explanation"))
    visible_assistant_content = assistant_content.strip() or explanation or ""
    persisted_messages: list[dict] = [
        {
            "id": persisted_user_message_id,
            "role": "user",
            "content": message,
            "status": "complete",
            "timestamp": timestamp,
            **(
                {"visibility": message_visibility}
                if message_visibility == "hidden"
                else {}
            ),
        },
        {
            "id": persisted_assistant_message_id,
            "role": "assistant",
            "content": visible_assistant_content,
            "status": "error",
            "timestamp": timestamp,
            "toolCalls": tool_calls or [],
            "error": str(error_event.get("error") or ""),
        },
    ]
    assistant_context = error_event.get("assistant_context")
    if isinstance(assistant_context, dict):
        persisted_messages.append(
            ConversationService.build_assistant_error_diagnostic_message(
                message_id=f"diag-{persisted_assistant_message_id}",
                related_message_id=persisted_assistant_message_id,
                timestamp=timestamp,
                diagnostics=assistant_context,
            )
        )

    try:
        with user_scoped_session(user_id) as persistence_db:
            ConversationService.add_messages(
                persistence_db,
                user_id,
                conversation_uuid,
                persisted_messages,
            )
    except Exception:
        logger.warning(
            "Failed to persist terminal chat stream error",
            exc_info=True,
            extra={"conversation_id": str(conversation_uuid)},
        )


def _build_title_cache_key(user_msg: str, assistant_msg: str) -> str:
    combined = f"{user_msg}\n{assistant_msg}"
    return hashlib.sha256(combined.encode("utf-8")).hexdigest()


def _get_cached_title(cache_key: str) -> _TitleCacheEntry | None:
    now = time.time()
    entry = TITLE_CACHE.get(cache_key)
    if not entry:
        return None
    if now - entry["timestamp"] > TITLE_CACHE_TTL_SECONDS:
        TITLE_CACHE.pop(cache_key, None)
        return None
    return entry


def _set_cached_title(cache_key: str, title: str) -> None:
    if len(TITLE_CACHE) >= TITLE_CACHE_MAX_ENTRIES:
        oldest_key = min(TITLE_CACHE.items(), key=lambda item: item[1]["timestamp"])[0]
        TITLE_CACHE.pop(oldest_key, None)
    TITLE_CACHE[cache_key] = {"title": title, "timestamp": time.time()}


def _should_insert_synthetic_tool_newline(
    assistant_content: str, token_content: str
) -> bool:
    """Mirror the client-side tool-boundary newline rule for persisted content."""
    return (
        bool(assistant_content)
        and not assistant_content.endswith("\n")
        and not token_content.startswith("\n")
    )


def _sanitize_title(raw_title: str) -> str:
    title = (raw_title or "").strip()
    if not title:
        raise ValueError("Empty title returned")
    if title.lower().startswith("title:"):
        title = title.split(":", 1)[1].strip()
    title = title.strip("\"'").strip()
    if "\n" in title:
        title = title.splitlines()[0].strip()
    title = " ".join(title.split())

    words = title.split()
    if len(words) > ChatConstants.TITLE_MAX_WORDS:
        title = " ".join(words[: ChatConstants.TITLE_MAX_WORDS])

    if not title:
        raise ValueError("Invalid title after sanitization")
    if len(title) > 100:
        title = title[:100].rstrip()
    return title


@router.post("/stream")
async def stream_chat(
    request: Request,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    _rate_limit: None = Depends(rate_limit_module.chat_stream_rate_limit),
):
    """Stream a chat response with SSE and tool events.

    Args:
        request: Incoming request with JSON payload.
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        StreamingResponse emitting SSE events.

    Raises:
        BadRequestError: For missing message.
        ConversationNotFoundError: If conversation is invalid.
    """
    data = await request.json()
    message = data.get("message")
    conversation_id = data.get("conversation_id")
    user_message_id = data.get("user_message_id")
    assistant_message_id = data.get("assistant_message_id")
    message_visibility = data.get("message_visibility")
    history = data.get("history", [])
    open_context = data.get("open_context") or {}
    attachments = data.get("attachments") or []
    current_location = data.get("current_location")
    current_location_levels = data.get("current_location_levels")
    current_weather = data.get("current_weather")
    current_timezone = data.get("current_timezone")

    if not message:
        raise BadRequestError("Message required")

    normalized_message_visibility = (
        message_visibility.strip().lower()
        if isinstance(message_visibility, str) and message_visibility.strip()
        else None
    )
    if normalized_message_visibility not in {"hidden", "visible", None}:
        normalized_message_visibility = None

    chat_messages_total.inc()

    conversation_uuid = None
    user_agent = request.headers.get("user-agent")
    app_version = request.headers.get("x-app-version")
    now = datetime.now(UTC)
    conversation_messages = None
    # Keep all request-time DB work inside a short-lived session before returning
    # StreamingResponse. FastAPI keeps yield dependencies alive for the full stream.
    with user_scoped_session(user_id) as db:
        if conversation_id:
            conversation_uuid = parse_uuid(conversation_id, "conversation", "id")
            conversation = ConversationService.get_conversation(
                db,
                user_id,
                conversation_uuid,
            )
            conversation_messages = list(conversation.messages or [])

        settings_record = UserSettingsService.get_settings(db, user_id)
        onboarding_state = OnboardingService.get_onboarding_state(db, user_id)
        require_completed_soul_calibration(onboarding_state)

        enabled_skills = SettingsService.resolve_enabled_skills(
            settings_record,
            db=db,
            user_id=user_id,
        )
        skill_catalog = SkillCatalogService.list_skills(settings.skills_dir)
        skill_catalog_by_id = {
            str(skill["id"]): skill
            for skill in skill_catalog
            if isinstance(skill, dict)
        }
        runtime_states = RuntimeCapabilityService.list_runtime_states(
            db,
            user_id=user_id,
            settings_record=settings_record,
        )
        runtime_capabilities: list[dict[str, object]] = []
        for runtime_state in runtime_states:
            if runtime_state.skill_id not in enabled_skills:
                continue
            catalog_entry = skill_catalog_by_id.get(runtime_state.skill_id, {})
            runtime_capabilities.append(
                {
                    "skill_id": runtime_state.skill_id,
                    "name": str(catalog_entry.get("name", runtime_state.skill_id)),
                    "description": str(catalog_entry.get("description", "")),
                    "tags": list(catalog_entry.get("tags", [])),
                    "triggers": list(catalog_entry.get("triggers", [])),
                    "required_toolsets": list(
                        catalog_entry.get("required_toolsets", [])
                    ),
                    "enabled": runtime_state.enabled,
                    "installed": runtime_state.installed,
                    "availability_status": runtime_state.availability_status,
                    "availability_reason": runtime_state.availability_reason,
                    "availability_remediation": runtime_state.availability_remediation,
                }
            )
        resolver_result = CapabilityResolverService.resolve_for_turn(
            user_message=message,
            enabled_skill_ids=enabled_skills,
            runtime_capabilities=runtime_capabilities,
            open_context=open_context,
            attachments=attachments,
            onboarding_state=onboarding_state,
        )
        blocked_skill_summaries = list(
            resolver_result.get(
                "blocked_skill_summaries",
                resolver_result.get("blocked_skills", []),
            )
        )
        selected_skill_ids = list(resolver_result.get("selected_skill_ids", []))
        executable_skill_ids = list(resolver_result.get("executable_skill_ids", []))
        initial_executable_skill_ids = list(executable_skill_ids)
        initial_blocked_skill_summaries = list(blocked_skill_summaries)
        ai_gateway = AIProviderGateway(settings)
        capability_loader_result = CapabilityLoaderService.load_for_turn(
            selected_skill_ids=selected_skill_ids,
            executable_skill_ids=executable_skill_ids,
            tool_definition_resolver=getattr(
                ai_gateway,
                "get_chat_tool_definitions",
                None,
            ),
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

        def provider_key_lookup(provider: AIProvider) -> str | None:
            with user_scoped_session(user_id) as provider_db:
                return UserAIProviderKeyService.get_active_key(
                    provider_db,
                    user_id,
                    provider,
                )

        try:
            chat_resolution = ai_gateway.resolve_chat(
                settings_record=settings_record,
                provider_key_lookup=provider_key_lookup,
            )
            if conversation_uuid is not None:
                ConversationService.set_ai_provider_model(
                    db,
                    user_id,
                    conversation_uuid,
                    provider=chat_resolution.provider,
                    model=chat_resolution.model,
                )
        except Exception as error:
            error_event = build_chat_stream_error_event(error)

            async def error_generator():
                chat_stream_errors_total.labels(type="server_error").inc()
                _persist_terminal_stream_error(
                    user_id=user_id,
                    conversation_uuid=conversation_uuid,
                    message=message,
                    user_message_id=user_message_id,
                    assistant_message_id=assistant_message_id,
                    message_visibility=normalized_message_visibility,
                    assistant_content="",
                    tool_calls=[],
                    error_event=error_event,
                )
                yield f"event: error\ndata: {json.dumps(error_event)}\n\n"

            return StreamingResponse(
                error_generator(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "X-Accel-Buffering": "no",
                },
            )

        executable_skill_ids, blocked_skill_summaries = (
            apply_chat_model_skill_compatibility(
                provider=chat_resolution.provider,
                model=chat_resolution.model,
                executable_skill_ids=executable_skill_ids,
                blocked_skill_summaries=blocked_skill_summaries,
            )
        )
        compatibility_changed = (
            executable_skill_ids != initial_executable_skill_ids
            or blocked_skill_summaries != initial_blocked_skill_summaries
        )
        if compatibility_changed:
            assembled_inputs, prepared_request = assemble_prepared_request(
                db=db,
                user_id=user_id,
                message=message,
                conversation_id=conversation_id,
                conversation_messages=conversation_messages,
                history=history,
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
                provider=chat_resolution.provider,
                model=chat_resolution.model,
                selected_skill_ids=selected_skill_ids,
                executable_skill_ids=executable_skill_ids,
                blocked_skill_summaries=blocked_skill_summaries,
                ai_gateway=ai_gateway,
            )
        else:
            prepared_request = RequestAssemblyService.build_prepared_request(
                provider=chat_resolution.provider,
                model=chat_resolution.model,
                assembled_inputs=assembled_inputs,
                executable_skill_ids=executable_skill_ids,
                capability_loader_result=capability_loader_result,
                tool_definition_resolver=getattr(
                    ai_gateway,
                    "get_chat_tool_definitions",
                    None,
                ),
            )
        tool_context = ToolExecutionContext(
            user_id=user_id,
            db_session_factory=lambda: user_scoped_session(user_id),
            open_context=open_context,
            attachments=attachments,
            conversation_id=conversation_uuid,
            user_message_id=user_message_id,
            message_visibility=normalized_message_visibility,
            user_agent=user_agent,
            app_version=app_version,
            current_location=current_location,
            current_location_levels=current_location_levels,
            current_weather=current_weather,
            current_timezone=current_timezone,
            selected_skill_ids=selected_skill_ids,
            executable_skill_ids=executable_skill_ids,
            blocked_skill_summaries=blocked_skill_summaries,
            enabled_skill_ids=list(enabled_skills),
            runtime_capabilities=runtime_capabilities,
            onboarding_state=onboarding_state,
        )
        trimmed_history_count = max(
            len(assembled_inputs.conversation_history)
            - len(prepared_request.conversation_history),
            0,
        )
        RequestBudgetFeedbackService.log_budget_decision(
            stage="prepared",
            report=prepared_request.budget_report,
            conversation_id=conversation_id,
            trimmed_history_count=trimmed_history_count,
        )
        if conversation_uuid is not None and trimmed_history_count > 0:
            compacted_conversation = (
                ConversationCompactionService.compact_conversation_history(
                    db=db,
                    user_id=user_id,
                    conversation_id=conversation_uuid,
                    replay_messages_to_compact=trimmed_history_count,
                )
            )
            assembled_inputs, prepared_request = assemble_prepared_request(
                db=db,
                user_id=user_id,
                message=message,
                conversation_id=conversation_id,
                conversation_messages=compacted_conversation.messages,
                history=history,
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
                provider=chat_resolution.provider,
                model=chat_resolution.model,
                selected_skill_ids=selected_skill_ids,
                executable_skill_ids=executable_skill_ids,
                blocked_skill_summaries=blocked_skill_summaries,
                ai_gateway=ai_gateway,
                compaction_applied=True,
            )
            trimmed_history_count = max(
                len(assembled_inputs.conversation_history)
                - len(prepared_request.conversation_history),
                0,
            )
            RequestBudgetFeedbackService.log_budget_decision(
                stage="compaction_retry",
                report=prepared_request.budget_report,
                conversation_id=conversation_id,
                trimmed_history_count=trimmed_history_count,
            )
        if not prepared_request.budget_report.within_budget:
            RequestBudgetFeedbackService.log_budget_decision(
                stage="overflow",
                report=prepared_request.budget_report,
                conversation_id=conversation_id,
                trimmed_history_count=trimmed_history_count,
            )
            raise BadRequestError(
                RequestBudgetFeedbackService.build_overflow_message(
                    prepared_request.budget_report
                )
            )
        tool_context.prompt_preview_payload = build_prompt_preview_payload(
            assembled_inputs=assembled_inputs,
            prepared_request=prepared_request,
        )

    stream_started_at = time.perf_counter()

    async def event_generator():
        """Generate SSE events."""
        assistant_content_parts: list[str] = []
        needs_newline_before_next_token = False
        tool_call_order: list[str] = []
        tool_calls_by_id: dict[str, dict] = {}

        try:
            async for event in ai_gateway.stream_chat_with_tools(
                message=prepared_request.current_user_message,
                conversation_history=(
                    prepared_request.bootstrap_history
                    + prepared_request.conversation_history
                ),
                system_prompt=prepared_request.system_prompt,
                allowed_skills=executable_skill_ids,
                tool_definitions=prepared_request.tool_definitions,
                tool_context=tool_context,
                settings_record=settings_record,
                provider_key_lookup=provider_key_lookup,
                chat_resolution=chat_resolution,
            ):
                event_type = event.get("type")

                if event_type == "token":
                    # Stream text token
                    token_content = event.get("content")
                    if isinstance(token_content, str) and token_content:
                        current_content = "".join(assistant_content_parts)
                        should_insert_newline = (
                            needs_newline_before_next_token
                            and _should_insert_synthetic_tool_newline(
                                current_content, token_content
                            )
                        )
                        if should_insert_newline:
                            assistant_content_parts.append("\n\n")
                        assistant_content_parts.append(token_content)
                        needs_newline_before_next_token = False
                    yield f"event: token\ndata: {json.dumps(event)}\n\n"

                elif event_type == "tool_call":
                    # Tool execution started
                    tool_call_id = event.get("id")
                    if isinstance(tool_call_id, str) and tool_call_id:
                        tool_call_order.append(tool_call_id)
                        tool_calls_by_id[tool_call_id] = {
                            "id": tool_call_id,
                            "name": event.get("name"),
                            "parameters": event.get("parameters"),
                            "status": event.get("status"),
                        }
                    yield f"event: tool_call\ndata: {json.dumps(event)}\n\n"

                elif event_type == "tool_result":
                    # Tool execution completed
                    tool_call_id = event.get("id")
                    if isinstance(tool_call_id, str) and tool_call_id:
                        existing = tool_calls_by_id.get(tool_call_id)
                        if existing is None:
                            tool_call_order.append(tool_call_id)
                            existing = {
                                "id": tool_call_id,
                                "name": event.get("name"),
                                "parameters": None,
                            }
                        existing["result"] = event.get("result")
                        existing["status"] = event.get("status")
                        tool_calls_by_id[tool_call_id] = existing
                    yield f"event: tool_result\ndata: {json.dumps(event)}\n\n"

                elif event_type in CUSTOM_CHAT_STREAM_EVENT_TYPES or (
                    event_type in ONBOARDING_STREAM_EVENT_TYPES
                ):
                    if event_type == "tool_status":
                        event_data = event.get("data", {})
                        if isinstance(event_data, dict):
                            status = event_data.get("status")
                            if isinstance(status, str) and status.lower() != "running":
                                needs_newline_before_next_token = True
                    data = json.dumps(event.get("data", {}))
                    yield f"event: {event_type}\ndata: {data}\n\n"

                elif event_type == "error":
                    # Error occurred
                    chat_stream_errors_total.labels(type="stream_error").inc()
                    structured_event = (
                        event
                        if event.get("version") == 2
                        and isinstance(event.get("assistant_context"), dict)
                        else build_chat_stream_error_event(
                            str(event.get("error") or "Unknown stream error"),
                            provider=chat_resolution.provider,
                            category=event.get("category")
                            if isinstance(event.get("category"), str)
                            else None,
                        )
                    )
                    _persist_terminal_stream_error(
                        user_id=user_id,
                        conversation_uuid=conversation_uuid,
                        message=message,
                        user_message_id=user_message_id,
                        assistant_message_id=assistant_message_id,
                        message_visibility=normalized_message_visibility,
                        assistant_content="".join(assistant_content_parts),
                        tool_calls=[
                            tool_calls_by_id[call_id]
                            for call_id in tool_call_order
                            if call_id in tool_calls_by_id
                        ],
                        error_event=structured_event,
                    )
                    yield f"event: error\ndata: {json.dumps(structured_event)}\n\n"
                    return

            if conversation_uuid is not None:
                timestamp = datetime.now(UTC).isoformat()
                persisted_user_message_id = (
                    user_message_id.strip()
                    if isinstance(user_message_id, str) and user_message_id.strip()
                    else str(uuid4())
                )
                persisted_assistant_message_id = (
                    assistant_message_id.strip()
                    if isinstance(assistant_message_id, str)
                    and assistant_message_id.strip()
                    else str(uuid4())
                )
                persisted_bootstrap_message = (
                    RequestAssemblyService.build_persisted_bootstrap_message(
                        bootstrap_history=prepared_request.bootstrap_history,
                        timestamp=timestamp,
                        message_id=str(uuid4()),
                    )
                )
                persisted_tool_calls = [
                    tool_calls_by_id[call_id]
                    for call_id in tool_call_order
                    if call_id in tool_calls_by_id
                ]
                persisted_messages = []
                if persisted_bootstrap_message is not None:
                    persisted_messages.append(persisted_bootstrap_message)
                persisted_messages.extend(
                    [
                        {
                            "id": persisted_user_message_id,
                            "role": "user",
                            "content": message,
                            "status": "complete",
                            "timestamp": timestamp,
                            **(
                                {"visibility": normalized_message_visibility}
                                if normalized_message_visibility == "hidden"
                                else {}
                            ),
                        },
                        {
                            "id": persisted_assistant_message_id,
                            "role": "assistant",
                            "content": "".join(assistant_content_parts),
                            "status": "complete",
                            "timestamp": timestamp,
                            "toolCalls": persisted_tool_calls,
                        },
                    ]
                )
                with user_scoped_session(user_id) as persistence_db:
                    ConversationService.add_messages(
                        persistence_db,
                        user_id,
                        conversation_uuid,
                        persisted_messages,
                    )
                    deliver_assistant_reply_notification(
                        db=persistence_db,
                        user_id=user_id,
                        conversation_id=str(conversation_uuid),
                        assistant_message_id=persisted_assistant_message_id,
                        assistant_content="".join(assistant_content_parts),
                        message_visibility=normalized_message_visibility,
                        user_settings_service=UserSettingsService,
                        device_token_service=DeviceTokenService,
                        notification_policy_service=NotificationPolicyService,
                        notification_delivery_service=NotificationDeliveryService,
                    )

            # Stream complete
            yield "event: complete\ndata: {}\n\n"

        except Exception as e:
            error_event = build_chat_stream_error_event(
                e,
                provider=chat_resolution.provider,
            )
            chat_stream_errors_total.labels(type="server_error").inc()
            _persist_terminal_stream_error(
                user_id=user_id,
                conversation_uuid=conversation_uuid,
                message=message,
                user_message_id=user_message_id,
                assistant_message_id=assistant_message_id,
                message_visibility=normalized_message_visibility,
                assistant_content="".join(assistant_content_parts),
                tool_calls=[
                    tool_calls_by_id[call_id]
                    for call_id in tool_call_order
                    if call_id in tool_calls_by_id
                ],
                error_event=error_event,
            )
            yield f"event: error\ndata: {json.dumps(error_event)}\n\n"
        finally:
            chat_streaming_duration_seconds.observe(
                max(0, time.perf_counter() - stream_started_at)
            )

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # Disable nginx buffering
        },
    )


@router.post("/generate-title")
async def generate_title(
    request: Request,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _rate_limit: None = Depends(rate_limit_module.chat_generate_title_rate_limit),
):
    """Generate a concise title for a conversation using Gemini.

    Args:
        request: Incoming request with conversation_id.
        db: Database session.
        user_id: Current authenticated user ID.

    Returns:
        Title payload with fallback flag.

    Raises:
        BadRequestError: For missing conversation_id or insufficient messages.
        ConversationNotFoundError: If not found.
    """
    data = await request.json()
    conversation_id = data.get("conversation_id")

    if not conversation_id:
        raise BadRequestError("conversation_id required")

    # Get conversation and verify ownership
    conversation_uuid = parse_uuid(conversation_id, "conversation", "id")
    conversation = ConversationService.get_conversation(db, user_id, conversation_uuid)

    if conversation.title_generated and conversation.title:
        return {"title": conversation.title, "fallback": False}

    # Find the first actual user/assistant pair rather than trusting positions.
    messages = ConversationService.visible_messages(conversation.messages)

    if not messages or len(messages) < 2:
        raise BadRequestError("Need at least 2 messages to generate title")

    user_msg, assistant_msg = select_title_messages(messages)
    settings_record = UserSettingsService.get_settings(db, user_id)
    cache_key = _build_title_cache_key(user_msg, assistant_msg)
    cached = _get_cached_title(cache_key)
    if cached:
        cached_title = cached["title"]
        ConversationService.set_title(
            db,
            user_id,
            conversation_uuid,
            cached_title,
            generated=True,
        )
        return {"title": cached_title, "fallback": False}

    try:
        ai_gateway = AIProviderGateway(settings, google_client_factory=genai.Client)

        def provider_key_lookup(provider: AIProvider) -> str | None:
            return UserAIProviderKeyService.get_active_key(db, user_id, provider)

        preferred_provider = None
        if isinstance(conversation.ai_provider, str):
            candidate = conversation.ai_provider.strip().lower()
            if candidate in VALID_AI_PROVIDERS:
                preferred_provider = cast(AIProvider, candidate)
        title_result = await ai_gateway.generate_title(
            user_message=user_msg,
            assistant_message=assistant_msg,
            settings_record=settings_record,
            preferred_provider=preferred_provider,
            provider_key_lookup=provider_key_lookup,
        )
        raw_title = title_result.raw_title
        title = _sanitize_title(raw_title)

        # Update conversation title
        ConversationService.set_title(
            db,
            user_id,
            conversation_uuid,
            title,
            generated=True,
        )
        _set_cached_title(cache_key, title)

        return {"title": title, "fallback": False}

    except Exception as error:
        logger.warning(
            "Title generation failed, using fallback",
            exc_info=error,
            extra={
                "conversation_id": str(conversation_uuid),
                "user_id": user_id,
                "message_length": len(user_msg),
                "error_type": type(error).__name__,
            },
        )
        # Fallback to first message snippet
        fallback_title = user_msg[:50] + ("..." if len(user_msg) > 50 else "")
        ConversationService.set_title(
            db,
            user_id,
            conversation_uuid,
            fallback_title,
            generated=False,
        )

        return {"title": fallback_title, "fallback": True}
