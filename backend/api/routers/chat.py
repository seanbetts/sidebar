"""Chat router with SSE streaming support."""
import json
import os
from datetime import datetime, timezone
from fastapi import APIRouter, Request, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from google import genai
from google.genai import types
from api.config import Settings, settings
from api.services.claude_client import ClaudeClient
from api.services.user_settings_service import UserSettingsService
from api.services.skill_catalog_service import SkillCatalogService
from api.services.prompt_context_service import PromptContextService
from api.auth import verify_bearer_token
from api.db.session import get_db
from api.db.dependencies import get_current_user_id
from api.models.conversation import Conversation


router = APIRouter(prefix="/chat", tags=["chat"])


def _build_history(messages, user_message_id, latest_message):
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
    catalog = SkillCatalogService.list_skills(settings.skills_dir)
    all_ids = [skill["id"] for skill in catalog]
    if not settings_record or settings_record.enabled_skills is None:
        return all_ids
    return [skill_id for skill_id in settings_record.enabled_skills if skill_id in all_ids]


 




@router.post("/stream")
async def stream_chat(
    request: Request,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """
    Stream chat response with tool calls via SSE.

    Headers:
        Authorization: Bearer {token}

    Body:
        {
            "message": "User message",
            "conversation_id": "uuid",  # Optional conversation id
            "user_message_id": "uuid",  # Optional message id to avoid duplicates
            "history": [...]            # Optional conversation history
        }

    SSE Events:
        - token: Streaming text tokens
        - tool_call: Tool execution started
        - tool_result: Tool execution completed
        - complete: Stream finished
        - error: Error occurred
    """
    data = await request.json()
    message = data.get("message")
    conversation_id = data.get("conversation_id")
    user_message_id = data.get("user_message_id")
    history = data.get("history", [])
    open_context = data.get("open_context") or {}
    current_location = data.get("current_location")
    current_location_levels = data.get("current_location_levels")
    current_weather = data.get("current_weather")
    current_timezone = data.get("current_timezone")

    if not message:
        raise HTTPException(status_code=400, detail="Message required")

    if conversation_id:
        conversation = db.query(Conversation).filter(
            Conversation.id == conversation_id,
            Conversation.user_id == user_id
        ).first()

        if not conversation:
            raise HTTPException(status_code=404, detail="Conversation not found")

        history = _build_history(conversation.messages, user_message_id, message)

    settings_record = UserSettingsService.get_settings(db, user_id)
    user_agent = request.headers.get("user-agent")
    now = datetime.now(timezone.utc)
    system_prompt, first_message_prompt = PromptContextService.build_prompts(
        db=db,
        user_id=user_id,
        open_context=open_context,
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
                    "server_tool_start",
                    "server_tool_end",
                }:
                    yield f"event: {event_type}\ndata: {json.dumps(event.get('data', {}))}\n\n"

                elif event_type == "error":
                    # Error occurred
                    yield f"event: error\ndata: {json.dumps(event)}\n\n"
                    return

            # Stream complete
            yield f"event: complete\ndata: {{}}\n\n"

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
    """
    Generate a concise title for a conversation using Gemini Flash.

    Body:
        {
            "conversation_id": "uuid"
        }

    Returns:
        {
            "title": "Generated title",
            "fallback": false  # true if fallback was used
        }
    """
    data = await request.json()
    conversation_id = data.get("conversation_id")

    if not conversation_id:
        raise HTTPException(status_code=400, detail="conversation_id required")

    # Get conversation and verify ownership
    print(f"DEBUG: Looking for conversation_id={conversation_id}, user_id={user_id}")
    conversation = db.query(Conversation).filter(
        Conversation.id == conversation_id,
        Conversation.user_id == user_id
    ).first()

    if not conversation:
        # Check if conversation exists at all
        any_conv = db.query(Conversation).filter(Conversation.id == conversation_id).first()
        if any_conv:
            print(f"DEBUG: Conversation exists but belongs to user_id={any_conv.user_id}")
        else:
            print(f"DEBUG: Conversation {conversation_id} does not exist in database")
        raise HTTPException(status_code=404, detail="Conversation not found")

    # Get first user and assistant messages from JSONB array
    messages = conversation.messages

    if not messages or len(messages) < 2:
        raise HTTPException(status_code=400, detail="Need at least 2 messages to generate title")

    user_msg = messages[0].get('content', '')
    assistant_msg = messages[1].get('content', '')

    try:
        # Initialize Gemini client
        api_key = os.getenv("GOOGLE_API_KEY")
        if not api_key:
            raise ValueError("GOOGLE_API_KEY not configured")

        client = genai.Client(api_key=api_key)

        # Generate title with Gemini Flash
        response = client.models.generate_content(
            model='gemini-3-flash-preview',
            contents=f"""Based on this conversation exchange, generate a concise, descriptive title of 3-5 words that captures the main topic.

User: {user_msg[:200]}
Assistant: {assistant_msg[:200]}

Title (3-5 words only, no quotes):""",
            config=types.GenerateContentConfig(
                temperature=0.3,
                max_output_tokens=20
            )
        )

        title = response.text.strip()

        # Update conversation title
        conversation.title = title
        conversation.title_generated = True
        db.commit()

        return {"title": title, "fallback": False}

    except Exception as e:
        # Fallback to first message snippet
        fallback_title = user_msg[:50] + ("..." if len(user_msg) > 50 else "")
        conversation.title = fallback_title
        conversation.title_generated = False
        db.commit()

        # Log the error but don't fail the request
        print(f"Title generation failed: {e}")

        return {"title": fallback_title, "fallback": True}
