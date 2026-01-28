"""Events router for near-realtime updates (SSE)."""
# ruff: noqa: B008

import asyncio
import json

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db, set_session_user_id
from api.services.change_bus import change_bus

router = APIRouter(prefix="/events", tags=["events"])


@router.get("")
async def stream_events(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Stream change events via server-sent events (SSE)."""
    set_session_user_id(db, user_id)

    async def event_generator():
        queue = await change_bus.subscribe(user_id)
        try:
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=15.0)
                    data = json.dumps(event)
                    yield f"event: change\ndata: {data}\n\n"
                except TimeoutError:
                    yield ": keep-alive\n\n"
        finally:
            await change_bus.unsubscribe(user_id, queue)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
