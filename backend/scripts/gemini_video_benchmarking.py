#!/usr/bin/env python3
"""Deterministic helpers for Gemini video benchmark runs."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BenchmarkVideo:
    """Video under benchmark."""

    video_id: str
    url: str
    title: str
    duration_seconds: int
    anchor_regions: tuple["AnchorRegion", ...] = ()
    reference_transcript_path: str | None = None


@dataclass(frozen=True)
class BenchmarkCombination:
    """Window and overlap candidate."""

    window_seconds: int
    overlap_seconds: int

    @property
    def label(self) -> str:
        """Return a stable human-readable combination label."""
        return f"{self.window_seconds}s / {self.overlap_seconds}s"


@dataclass(frozen=True)
class BenchmarkWindow:
    """Single clipped video window."""

    start_seconds: int
    end_seconds: int

    @property
    def duration_seconds(self) -> int:
        """Return the window duration."""
        return self.end_seconds - self.start_seconds


@dataclass(frozen=True)
class AnchorRegion:
    """Named anchor checks for a time range."""

    name: str
    start_seconds: int
    end_seconds: int
    anchors: tuple[str, ...]


@dataclass(frozen=True)
class PlannedRun:
    """One benchmark run for a video, combination, and concurrency level."""

    video: BenchmarkVideo
    combination: BenchmarkCombination
    concurrency: int
    run_number: int
    windows: tuple[BenchmarkWindow, ...]


def parse_duration_seconds(value: str | int) -> int:
    """Parse a duration from seconds, MM:SS, or HH:MM:SS."""
    if isinstance(value, int):
        if value <= 0:
            raise ValueError("Invalid duration: must be positive")
        return value

    parts = value.strip().split(":")
    if len(parts) not in {1, 2, 3}:
        raise ValueError(f"Invalid duration: {value}")
    if not all(part.isdigit() for part in parts):
        raise ValueError(f"Invalid duration: {value}")

    numbers = [int(part) for part in parts]
    if len(numbers) == 1:
        total = numbers[0]
        seconds = total
        minutes = 0
    elif len(numbers) == 2:
        minutes, seconds = numbers
        total = minutes * 60 + seconds
    else:
        hours, minutes, seconds = numbers
        total = hours * 3600 + minutes * 60 + seconds

    if (
        total <= 0
        or (len(numbers) > 1 and seconds >= 60)
        or (len(numbers) == 3 and minutes >= 60)
    ):
        raise ValueError(f"Invalid duration: {value}")
    return total


def plan_windows(
    *,
    duration_seconds: int,
    window_seconds: int,
    overlap_seconds: int,
) -> tuple[BenchmarkWindow, ...]:
    """Plan deterministic clipped windows for a video."""
    if duration_seconds <= 0:
        raise ValueError("duration_seconds must be positive")
    if window_seconds <= 0:
        raise ValueError("window_seconds must be positive")
    if overlap_seconds < 0:
        raise ValueError("overlap_seconds must be non-negative")
    if overlap_seconds >= window_seconds:
        raise ValueError("overlap_seconds must be less than window_seconds")

    windows: list[BenchmarkWindow] = []
    step = window_seconds - overlap_seconds
    start = 0
    while start < duration_seconds:
        end = min(start + window_seconds, duration_seconds)
        windows.append(BenchmarkWindow(start_seconds=start, end_seconds=end))
        if end >= duration_seconds:
            break
        start += step
    return tuple(windows)


def expand_run_matrix(
    *,
    videos: list[BenchmarkVideo],
    combinations: list[BenchmarkCombination],
    concurrency_levels: list[int],
    repeat_count: int = 3,
) -> list[PlannedRun]:
    """Expand videos, combinations, concurrency levels, and repeats."""
    if repeat_count <= 0:
        raise ValueError("repeat_count must be positive")
    if any(level <= 0 for level in concurrency_levels):
        raise ValueError("concurrency levels must be positive")

    runs: list[PlannedRun] = []
    for video in videos:
        for combination in combinations:
            windows = plan_windows(
                duration_seconds=video.duration_seconds,
                window_seconds=combination.window_seconds,
                overlap_seconds=combination.overlap_seconds,
            )
            for concurrency in concurrency_levels:
                for run_number in range(1, repeat_count + 1):
                    runs.append(
                        PlannedRun(
                            video=video,
                            combination=combination,
                            concurrency=concurrency,
                            run_number=run_number,
                            windows=windows,
                        )
                    )
    return runs
