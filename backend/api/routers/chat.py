"""Chat router with SSE streaming support."""
import asyncio
import hashlib
import json
import logging
import os
import time
from datetime import datetime, timezone
from fastapi import APIRouter, Request, Depends
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from google import genai
from google.genai import types
from api.config import settings
from api.services.claude_client import ClaudeClient
from api.services.user_settings_service import UserSettingsService
from api.services.skill_catalog_service import SkillCatalogService
from api.services.prompt_context_service import PromptContextService
from api.auth import verify_bearer_token
from api.db.session import get_db
from api.db.dependencies import get_current_user_id
from api.services.conversation_service import ConversationService
from api.exceptions import BadRequestError
from api.utils.validation import parse_uuid


router = APIRouter(prefix="/chat", tags=["chat"])
logger = logging.getLogger(__name__)

TITLE_CACHE_TTL_SECONDS = 60 * 60
TITLE_CACHE_MAX_ENTRIES = 512
TITLE_CACHE: dict[str, dict[str, object]] = {}


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


def _resolve_enabled_skills(settings_record):
    """Resolve enabled skills from settings against the skill catalog.

    Args:
        settings_record: User settings record or None.

    Returns:
        List of enabled skill IDs.
    """
    catalog = SkillCatalogService.list_skills(settings.skills_dir)
    all_ids = [skill["id"] for skill in catalog]
    if not settings_record or settings_record.enabled_skills is None:
        return all_ids
    return [skill_id for skill_id in settings_record.enabled_skills if skill_id in all_ids]


def _build_title_cache_key(user_msg: str, assistant_msg: str) -> str:
    combined = f"{user_msg}\n{assistant_msg}"
    return hashlib.sha256(combined.encode("utf-8")).hexdigest()


def _get_cached_title(cache_key: str) -> dict[str, object] | None:
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
        oldest_key = min(
            TITLE_CACHE.items(),
            key=lambda item: item[1]["timestamp"]
        )[0]
        TITLE_CACHE.pop(oldest_key, None)
    TITLE_CACHE[cache_key] = {
        "title": title,
        "timestamp": time.time()
    }


def _sanitize_title(raw_title: str) -> str:
    title = (raw_title or "").strip()
    if not title:
        raise ValueError("Empty title returned")
    if title.lower().startswith("title:"):
        title = title.split(":", 1)[1].strip()
    title = title.strip('"\'').strip()
    if "\n" in title:
        title = title.splitlines()[0].strip()
    title = " ".join(title.split())

    words = title.split()
    if len(words) > 5:
        title = " ".join(words[:5])

    if not title:
        raise ValueError("Invalid title after sanitization")
    if len(title) > 100:
        title = title[:100].rstrip()
    return title


def _is_retryable_error(error: Exception) -> bool:
    if isinstance(error, ValueError):
        return False
    error_name = error.__class__.__name__
    if error_name in {"AuthenticationError", "PermissionDenied", "InvalidArgument"}:
        return False
    return True


def _extract_response_text(response) -> str:
    text = getattr(response, "text", None)
    if text:
        return text

    candidates = getattr(response, "candidates", None) or []
    for candidate in candidates:
        content = getattr(candidate, "content", None)
        parts = getattr(content, "parts", None) or []
        for part in parts:
            part_text = getattr(part, "text", None)
            if part_text:
                return part_text
    return ""

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

    if conversation_id:
        conversation_uuid = parse_uuid(conversation_id, "conversation", "id")
        conversation = ConversationService.get_conversation(db, user_id, conversation_uuid)
        history = _build_history(conversation.messages, user_message_id, message)

    settings_record = UserSettingsService.get_settings(db, user_id)
    user_agent = request.headers.get("user-agent")
    now = datetime.now(timezone.utc)
    system_prompt, first_message_prompt = PromptContextService.build_prompts(
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
    enabled_skills = _resolve_enabled_skills(settings_record)
    if not history:
        history = [{"role": "user", "content": first_message_prompt}]

    # Create Claude client
    claude_client = ClaudeClient(settings)
    tool_context = {
        "db": db,
        "user_id": user_id,
        "open_context": open_context,
        "attachments": attachments,
        "user_agent": user_agent,
        "current_location": current_location,
        "current_location_levels": current_location_levels,
        "current_weather": current_weather,
        "current_timezone": current_timezone,
    }

    async def event_generator():
        """Generate SSE events."""
        try:
            async for event in claude_client.stream_with_tools(
                message,
                history,
                system_prompt=system_prompt,
                allowed_skills=enabled_skills,
                tool_context=tool_context,
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
                    "website_saved",
                    "note_deleted",
                    "website_deleted",
                    "ui_theme_set",
                    "scratchpad_updated",
                    "scratchpad_cleared",
                    "prompt_preview",
                    "tool_start",
                    "tool_end",
                }:
                    yield f"event: {event_type}\ndata: {json.dumps(event.get('data', {}))}\n\n"

                elif event_type == "error":
                    # Error occurred
                    yield f"event: error\ndata: {json.dumps(event)}\n\n"
                    return

            # Stream complete
            yield "event: complete\ndata: {}\n\n"

        except Exception as e:
            error_event = {"type": "error", "error": str(e)}
            yield f"event: error\ndata: {json.dumps(error_event)}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"  # Disable nginx buffering
        }
    )


@router.post("/generate-title")
async def generate_title(
    request: Request,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id)
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

    user_msg = messages[0].get('content', '')
    assistant_msg = messages[1].get('content', '')
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
        # Initialize Gemini client
        api_key = os.getenv("GOOGLE_API_KEY")
        if not api_key:
            raise ValueError("GOOGLE_API_KEY not configured")

        client = genai.Client(api_key=api_key)

        prompt = (
            "Generate ONLY a 3-5 word title for this conversation.\n"
            "Output the title directly without quotes, punctuation, or prefixes.\n\n"
            f"User: {user_msg[:200]}\n"
            f"Assistant: {assistant_msg[:200]}\n\n"
            "Title:"
        )

        response = None
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                response = client.models.generate_content(
                    model='gemini-3-flash-preview',
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=0,
                        max_output_tokens=20,
                        response_mime_type="text/plain",
                        automatic_function_calling=types.AutomaticFunctionCallingConfig(
                            disable=True
                        ),
                        thinking_config=types.ThinkingConfig(
                            thinking_budget=0
                        )
                    )
                )
                break
            except Exception as error:
                last_error = error
                if not _is_retryable_error(error) or attempt == 2:
                    raise
                backoff_seconds = 0.5 * (2 ** attempt)
                await asyncio.sleep(backoff_seconds)

        if response is None:
            if last_error:
                raise last_error
            raise ValueError("No response from title generator")

        raw_title = _extract_response_text(response)
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
