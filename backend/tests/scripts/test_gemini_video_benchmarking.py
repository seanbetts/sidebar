"""Tests for backend/scripts/gemini_video_benchmarking.py."""

from __future__ import annotations

import pytest

from scripts.gemini_video_benchmarking import (
    BenchmarkCombination,
    BenchmarkVideo,
    expand_run_matrix,
    parse_duration_seconds,
    plan_windows,
)


def test_parse_duration_seconds_accepts_mm_ss_and_hh_mm_ss() -> None:
    assert parse_duration_seconds("20:20") == 1220
    assert parse_duration_seconds("1:02:03") == 3723
    assert parse_duration_seconds(95) == 95


def test_parse_duration_seconds_rejects_bad_values() -> None:
    with pytest.raises(ValueError, match="Invalid duration"):
        parse_duration_seconds("not-a-duration")


def test_plan_windows_keeps_final_partial_window() -> None:
    windows = plan_windows(duration_seconds=1220, window_seconds=240, overlap_seconds=30)

    assert [(item.start_seconds, item.end_seconds) for item in windows] == [
        (0, 240),
        (210, 450),
        (420, 660),
        (630, 870),
        (840, 1080),
        (1050, 1220),
    ]


def test_plan_windows_rejects_overlap_that_does_not_advance() -> None:
    with pytest.raises(ValueError, match="overlap_seconds must be less"):
        plan_windows(duration_seconds=300, window_seconds=120, overlap_seconds=120)


def test_expand_run_matrix_defaults_to_three_repeats() -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=360,
    )
    combination = BenchmarkCombination(window_seconds=120, overlap_seconds=30)

    runs = expand_run_matrix(
        videos=[video],
        combinations=[combination],
        concurrency_levels=[1, 4],
        repeat_count=3,
    )

    assert [run.run_number for run in runs] == [1, 2, 3, 1, 2, 3]
    assert [run.concurrency for run in runs] == [1, 1, 1, 4, 4, 4]
    assert all(run.video.video_id == "abc123" for run in runs)
