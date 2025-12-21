"""Chat router with SSE streaming support."""
import json
from fastapi import APIRouter, Request, Depends
from fastapi.responses import StreamingResponse
from api.config import Settings, settings
from api.services.claude_client import ClaudeClient
from api.auth import verify_bearer_token


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
