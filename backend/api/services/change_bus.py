"""In-memory change bus for near-realtime updates."""

from __future__ import annotations

import asyncio
from collections import defaultdict
from collections.abc import Iterable
from contextlib import suppress
from typing import Any


class ChangeBus:
    """Publish change events to in-memory subscribers."""

    def __init__(self, *, max_queue_size: int = 100) -> None:
        """Initialize the change bus with bounded subscriber queues."""
        self._subscribers: dict[str, set[asyncio.Queue[dict[str, Any]]]] = defaultdict(
            set
        )
        self._max_queue_size = max_queue_size
        self._lock = asyncio.Lock()

    async def subscribe(self, user_id: str) -> asyncio.Queue[dict[str, Any]]:
        """Register a subscriber for a user and return its queue."""
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(
            maxsize=self._max_queue_size
        )
        async with self._lock:
            self._subscribers[user_id].add(queue)
        return queue

    async def unsubscribe(
        self, user_id: str, queue: asyncio.Queue[dict[str, Any]]
    ) -> None:
        """Unregister a subscriber queue for a user."""
        async with self._lock:
            if user_id in self._subscribers:
                self._subscribers[user_id].discard(queue)
                if not self._subscribers[user_id]:
                    self._subscribers.pop(user_id, None)

    async def publish(self, user_id: str, event: dict[str, Any]) -> None:
        """Publish an event to all subscribers for the user."""
        async with self._lock:
            queues: Iterable[asyncio.Queue[dict[str, Any]]] = list(
                self._subscribers.get(user_id, set())
            )

        for queue in queues:
            if queue.full():
                with suppress(asyncio.QueueEmpty):
                    queue.get_nowait()
            try:
                queue.put_nowait(event)
            except asyncio.QueueFull:
                continue


change_bus = ChangeBus()
