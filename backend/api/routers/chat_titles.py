"""Chat title generation routes."""

# ruff: noqa: B008

from __future__ import annotations

import logging
import time
from typing import TypedDict, cast

from fastapi import APIRouter, Depends, Request
from google import genai
from sqlalchemy.orm import Session

from api.config import settings
from api.constants import ChatConstants
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError
from api.middleware import rate_limit as rate_limit_module
from api.services.agent.chat_title_service import (
    build_title_cache_key,
    sanitize_title,
)
from api.services.ai.gateway import AIProviderGateway
from api.services.ai.registry import VALID_AI_PROVIDERS, AIProvider
from api.services.chat_router_support import select_title_messages
from api.services.conversation_service import ConversationService
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


@router.post("/generate-title")
async def generate_title(
    request: Request,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _rate_limit: None = Depends(rate_limit_module.chat_generate_title_rate_limit),
):
    """Generate a concise title for a conversation using Gemini."""
    data = await request.json()
    conversation_id = data.get("conversation_id")

    if not conversation_id:
        raise BadRequestError("conversation_id required")

    conversation_uuid = parse_uuid(conversation_id, "conversation", "id")
    conversation = ConversationService.get_conversation(db, user_id, conversation_uuid)

    if conversation.title_generated and conversation.title:
        return {"title": conversation.title, "fallback": False}

    messages = ConversationService.visible_messages(conversation.messages)
    if not messages or len(messages) < 2:
        raise BadRequestError("Need at least 2 messages to generate title")

    user_msg, assistant_msg = select_title_messages(messages)
    settings_record = UserSettingsService.get_settings(db, user_id)
    cache_key = build_title_cache_key(user_msg, assistant_msg)
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
        title = sanitize_title(title_result.raw_title)
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
        fallback_title = user_msg[:50] + ("..." if len(user_msg) > 50 else "")
        ConversationService.set_title(
            db,
            user_id,
            conversation_uuid,
            fallback_title,
            generated=False,
        )
        return {"title": fallback_title, "fallback": True}
