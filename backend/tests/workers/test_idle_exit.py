"""Tests for process-wide worker idle-exit tracking."""

import threading

from workers.idle_exit import IdleExitTracker


class FakeClock:
    """Controllable monotonic clock for idle-boundary tests."""

    def __init__(self) -> None:
        self.elapsed = 0.0

    def __call__(self) -> float:
        """Return the current fake monotonic time."""
        return self.elapsed

    def advance(self, seconds: float) -> None:
        """Advance the fake monotonic time."""
        self.elapsed += seconds


def test_tracker_never_exits_while_a_job_is_active() -> None:
    """An active job must prevent exit beyond the idle timeout."""
    clock = FakeClock()
    tracker = IdleExitTracker(30, monotonic=clock)
    tracker.job_started()
    clock.advance(60)

    assert tracker.should_exit() is False

    tracker.job_finished()
    assert tracker.should_exit() is False
    clock.advance(30)
    assert tracker.should_exit() is True


def test_tracker_timeout_zero_disables_idle_exit() -> None:
    """A zero timeout must preserve continuous worker polling."""
    clock = FakeClock()
    tracker = IdleExitTracker(0, monotonic=clock)
    clock.advance(86400)

    assert tracker.should_exit() is False


def test_job_start_resets_an_expired_idle_period() -> None:
    """Claiming new work must invalidate a previously expired idle period."""
    clock = FakeClock()
    tracker = IdleExitTracker(30, monotonic=clock)
    clock.advance(30)
    assert tracker.should_exit() is True

    tracker.job_started()

    assert tracker.should_exit() is False
    tracker.job_finished()
    assert tracker.should_exit() is False


def test_job_finish_starts_a_fresh_idle_period() -> None:
    """The idle grace period must begin when the last active job finishes."""
    clock = FakeClock()
    tracker = IdleExitTracker(30, monotonic=clock)
    tracker.job_started()
    clock.advance(45)
    tracker.job_finished()

    clock.advance(29)
    assert tracker.should_exit() is False
    clock.advance(1)
    assert tracker.should_exit() is True


def test_concurrent_job_finishes_cannot_make_active_count_negative() -> None:
    """Concurrent duplicate finishes must leave the tracker idle, not underflowed."""
    clock = FakeClock()
    tracker = IdleExitTracker(30, monotonic=clock)
    tracker.job_started()
    ready = threading.Barrier(3)

    def finish_job() -> None:
        ready.wait()
        tracker.job_finished()

    threads = [threading.Thread(target=finish_job) for _ in range(2)]
    for thread in threads:
        thread.start()
    ready.wait()
    for thread in threads:
        thread.join(timeout=1)
        assert thread.is_alive() is False

    clock.advance(30)
    assert tracker.should_exit() is True
