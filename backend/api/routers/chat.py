"""Chat router with SSE streaming support."""
import json
import os
from fastapi import APIRouter, Request, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from google import genai
from google.genai import types
from api.config import Settings, settings
from api.services.claude_client import ClaudeClient
from api.auth import verify_bearer_token
from api.db.session import get_db
from api.db.dependencies import get_current_user_id
from api.models.conversation import Conversation


router = APIRouter(prefix="/chat", tags=["chat"])


@router.post("/stream")
async def stream_chat(
    request: Request,
    user_id: str = Depends(verify_bearer_token)
):
    """
    Stream chat response with tool calls via SSE.

    Headers:
        Authorization: Bearer {token}

    Body:
        {
            "message": "User message",
            "history": [...]  # Optional conversation history
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
    history = data.get("history", [])

    if not message:
        return {"error": "Message required"}, 400

    # Create Claude client
    claude_client = ClaudeClient(settings)

    async def event_generator():
        """Generate SSE events."""
        try:
            async for event in claude_client.stream_with_tools(message, history):
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

                elif event_type in {"note_created", "note_updated", "website_saved"}:
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
