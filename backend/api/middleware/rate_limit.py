"""Per-user rate limiting helpers for high-cost authenticated endpoints."""

from __future__ import annotations

import math
import os
import time
from collections import defaultdict, deque
from collections.abc import Callable
from dataclasses import dataclass
from threading import Lock

from fastapi import Depends, HTTPException, Request

from api.db.dependencies import get_current_user_id


@dataclass(frozen=True)
class RateLimitPolicy:
    """Rate-limit budget for a request scope."""

    limit: int
    window_seconds: int


class InMemoryRateLimiter:
    """In-process rate limiter keyed by scope and authenticated subject."""

    def __init__(self, time_func: Callable[[], float] | None = None) -> None:
        """Initialize the limiter with an optional clock override."""
        self._time_func = time_func or time.monotonic
        self._buckets: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def reset(self) -> None:
        """Clear all buckets, primarily for tests."""
        with self._lock:
            self._buckets.clear()

    def check(self, key: str, policy: RateLimitPolicy) -> int | None:
        """Record a request and return retry delay when the budget is exhausted."""
        now = self._time_func()
        window_start = now - policy.window_seconds

        with self._lock:
            bucket = self._buckets[key]
            while bucket and bucket[0] <= window_start:
                bucket.popleft()

            if len(bucket) >= policy.limit:
                retry_after = max(
                    1,
                    int(math.ceil((bucket[0] + policy.window_seconds) - now)),
                )
                return retry_after

            bucket.append(now)
            return None


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    return max(1, value)


RATE_LIMIT_POLICIES: dict[str, RateLimitPolicy] = {
    "chat_stream": RateLimitPolicy(
        limit=_env_int("RATE_LIMIT_CHAT_STREAM_PER_MINUTE", 10),
        window_seconds=60,
    ),
    "chat_generate_title": RateLimitPolicy(
        limit=_env_int("RATE_LIMIT_CHAT_GENERATE_TITLE_PER_MINUTE", 20),
        window_seconds=60,
    ),
    "website_save": RateLimitPolicy(
        limit=_env_int("RATE_LIMIT_WEBSITE_SAVE_PER_MINUTE", 30),
        window_seconds=60,
    ),
    "file_upload": RateLimitPolicy(
        limit=_env_int("RATE_LIMIT_FILE_UPLOAD_PER_MINUTE", 20),
        window_seconds=60,
    ),
    "website_search": RateLimitPolicy(
        limit=_env_int("RATE_LIMIT_SEARCH_PER_MINUTE", 60),
        window_seconds=60,
    ),
    "conversation_search": RateLimitPolicy(
        limit=_env_int("RATE_LIMIT_SEARCH_PER_MINUTE", 60),
        window_seconds=60,
    ),
}

rate_limiter = InMemoryRateLimiter()


def _rate_limit_detail(
    *,
    scope: str,
    policy: RateLimitPolicy,
    retry_after_seconds: int,
) -> dict[str, object]:
    return {
        "error": {
            "code": "RATE_LIMITED",
            "message": "Rate limit exceeded",
            "details": {
                "scope": scope,
                "limit": policy.limit,
                "window_seconds": policy.window_seconds,
                "retry_after_seconds": retry_after_seconds,
            },
        }
    }


def build_rate_limit_dependency(scope: str):
    """Create a dependency that enforces the configured budget for a scope."""

    async def enforce_rate_limit(
        request: Request,
        user_id: str = Depends(get_current_user_id),  # noqa: B008
    ) -> None:
        policy = RATE_LIMIT_POLICIES[scope]
        subject = user_id or (request.client.host if request.client else "anonymous")
        retry_after_seconds = rate_limiter.check(f"{scope}:{subject}", policy)
        if retry_after_seconds is None:
            return

        raise HTTPException(
            status_code=429,
            detail=_rate_limit_detail(
                scope=scope,
                policy=policy,
                retry_after_seconds=retry_after_seconds,
            ),
            headers={"Retry-After": str(retry_after_seconds)},
        )

    return enforce_rate_limit


chat_stream_rate_limit = build_rate_limit_dependency("chat_stream")
chat_generate_title_rate_limit = build_rate_limit_dependency("chat_generate_title")
website_save_rate_limit = build_rate_limit_dependency("website_save")
file_upload_rate_limit = build_rate_limit_dependency("file_upload")
website_search_rate_limit = build_rate_limit_dependency("website_search")
conversation_search_rate_limit = build_rate_limit_dependency("conversation_search")
