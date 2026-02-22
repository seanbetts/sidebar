"""Chat router with SSE streaming support."""
# ruff: noqa: B008

import hashlib
import json
import logging
import time
from datetime import UTC, datetime
from typing import TypedDict, cast

from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
from google import genai
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.config import settings
from api.constants import ChatConstants
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError
from api.metrics import (
    chat_messages_total,
    chat_stream_errors_total,
    chat_streaming_duration_seconds,
)
from api.schemas.tool_context import ToolExecutionContext
from api.services.agent.prompt.composer import PromptContextService
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.registry import VALID_AI_PROVIDERS, AIProvider
from api.services.conversation_service import ConversationService
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


def _build_history(messages, user_message_id, latest_message):
    """Build sanitized chat history from stored messages.

    Args:
        messages: Conversation message list from the database.
        user_message_id: Optional message ID to exclude from history.
        latest_message: Latest user message to de-duplicate.

    Returns:
        List of history messages suitable for model input.
    """
    history = []
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

    if not user_message_id and history:
        last = history[-1]
        if last.get("role") == "user" and last.get("content") == latest_message:
            history = history[:-1]

    return history


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
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
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
    history = data.get("history", [])
    open_context = data.get("open_context") or {}
    attachments = data.get("attachments") or []
    current_location = data.get("current_location")
    current_location_levels = data.get("current_location_levels")
    current_weather = data.get("current_weather")
    current_timezone = data.get("current_timezone")

    if not message:
        raise BadRequestError("Message required")

    chat_messages_total.inc()

    conversation_uuid = None
    if conversation_id:
        conversation_uuid = parse_uuid(conversation_id, "conversation", "id")
        conversation = ConversationService.get_conversation(
            db, user_id, conversation_uuid
        )
        history = _build_history(conversation.messages, user_message_id, message)

    settings_record = UserSettingsService.get_settings(db, user_id)
    user_agent = request.headers.get("user-agent")
    app_version = request.headers.get("x-app-version")
    now = datetime.now(UTC)
    prompt_bundle = PromptContextService.build_prompts(
        db=db,
        user_id=user_id,
        open_context=open_context,
        attachments=attachments,
        user_agent=user_agent,
        current_location=current_location,
        current_location_levels=current_location_levels,
        current_weather=current_weather,
        now=now,
    )
    system_prompt = prompt_bundle["system_prompt"]["text"]
    first_message_prompt = prompt_bundle["first_message_prompt"]["text"]
    enabled_skills = SettingsService.resolve_enabled_skills(settings_record)
    if not history:
        history = [{"role": "user", "content": first_message_prompt}]

    ai_gateway = AIProviderGateway(settings)
    tool_context = ToolExecutionContext(
        db=db,
        user_id=user_id,
        open_context=open_context,
        attachments=attachments,
        conversation_id=conversation_uuid,
        user_message_id=user_message_id,
        user_agent=user_agent,
        app_version=app_version,
        current_location=current_location,
        current_location_levels=current_location_levels,
        current_weather=current_weather,
        current_timezone=current_timezone,
    )

    stream_started_at = time.perf_counter()

    def provider_key_lookup(provider: AIProvider) -> str | None:
        return UserAIProviderKeyService.get_active_key(db, user_id, provider)

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
        error_message = str(error)

        async def error_generator():
            chat_stream_errors_total.labels(type="server_error").inc()
            error_event = {"type": "error", "error": error_message}
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

    async def event_generator():
        """Generate SSE events."""
        try:
            async for event in ai_gateway.stream_chat_with_tools(
                message=message,
                conversation_history=history,
                system_prompt=system_prompt,
                allowed_skills=enabled_skills,
                tool_context=tool_context,
                settings_record=settings_record,
                provider_key_lookup=provider_key_lookup,
                chat_resolution=chat_resolution,
            ):
                event_type = event.get("type")

                if event_type == "token":
                    # Stream text token
                    yield f"event: token\ndata: {json.dumps(event)}\n\n"

                elif event_type == "tool_call":
                    # Tool execution started
                    yield f"event: tool_call\ndata: {json.dumps(event)}\n\n"

                elif event_type == "tool_result":
                    # Tool execution completed
                    yield f"event: tool_result\ndata: {json.dumps(event)}\n\n"

                elif event_type in {
                    "note_created",
                    "note_updated",
                    "note_pinned",
                    "note_moved",
                    "website_saved",
                    "website_pinned",
                    "website_archived",
                    "note_deleted",
                    "website_deleted",
                    "ingestion_updated",
                    "ui_theme_set",
                    "scratchpad_updated",
                    "scratchpad_cleared",
                    "prompt_preview",
                    "tool_start",
                    "tool_end",
                    "memory_created",
                    "memory_updated",
                    "memory_deleted",
                    "assistant_identity_updated",
                    "assistant_soul_updated",
                    "profile_user_settings_updated",
                    "other_preferences_updated",
                }:
                    data = json.dumps(event.get("data", {}))
                    yield f"event: {event_type}\ndata: {data}\n\n"

                elif event_type == "error":
                    # Error occurred
                    chat_stream_errors_total.labels(type="stream_error").inc()
                    yield f"event: error\ndata: {json.dumps(event)}\n\n"
                    return

            # Stream complete
            yield "event: complete\ndata: {}\n\n"

        except Exception as e:
            error_event = {"type": "error", "error": str(e)}
            chat_stream_errors_total.labels(type="server_error").inc()
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

    # Get first user and assistant messages from JSONB array
    messages = conversation.messages

    if not messages or len(messages) < 2:
        raise BadRequestError("Need at least 2 messages to generate title")

    user_msg = messages[0].get("content", "")
    assistant_msg = messages[1].get("content", "")
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
