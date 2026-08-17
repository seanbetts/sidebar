"""Thread-safe process-wide idle-exit tracking for queue workers."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable


class IdleExitTracker:
    """Track active jobs and determine when process-wide idle time has expired."""

    def __init__(
        self,
        timeout_seconds: float,
        *,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        """Initialize idle state using the supplied monotonic clock."""
        self._timeout_seconds = timeout_seconds
        self._monotonic = monotonic
        self._lock = threading.Lock()
        self._active_jobs = 0
        self._last_activity = monotonic()

    def job_started(self) -> None:
        """Record that a worker thread claimed a job."""
        with self._lock:
            self._active_jobs += 1
            self._last_activity = self._monotonic()

    def job_finished(self) -> None:
        """Record a completed job without allowing the active count to underflow."""
        with self._lock:
            if self._active_jobs == 0:
                return
            self._active_jobs -= 1
            self._last_activity = self._monotonic()

    def should_exit(self) -> bool:
        """Return whether the configured process-wide idle period has elapsed."""
        with self._lock:
            return (
                self._timeout_seconds > 0
                and self._active_jobs == 0
                and self._monotonic() - self._last_activity >= self._timeout_seconds
            )
