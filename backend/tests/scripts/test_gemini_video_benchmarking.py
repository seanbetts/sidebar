"""Tests for backend/scripts/gemini_video_benchmarking.py."""

from __future__ import annotations

import json

import pytest

from scripts.gemini_video_benchmarking import (
    AnchorRegion,
    BenchmarkCombination,
    BenchmarkVideo,
    BenchmarkWindow,
    CallResult,
    PricingProfile,
    TokenUsage,
    aggregate_run_summary,
    calculate_cost,
    calculate_output_cap,
    detect_repetition,
    expand_run_matrix,
    load_benchmark_config,
    normalize_anchor_text,
    order_call_results,
    parse_duration_seconds,
    plan_windows,
    score_anchor_region,
    write_reports,
)


def test_parse_duration_seconds_accepts_mm_ss_and_hh_mm_ss() -> None:
    assert parse_duration_seconds("20:20") == 1220
    assert parse_duration_seconds("1:02:03") == 3723
    assert parse_duration_seconds("95") == 95
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


def test_calculate_output_cap_scales_with_window_duration() -> None:
    assert calculate_output_cap(duration_seconds=90) == 900
    assert calculate_output_cap(duration_seconds=240) == 1152
    assert calculate_output_cap(duration_seconds=360) == 1728


def test_anchor_scoring_normalizes_case_punctuation_and_hyphens() -> None:
    text = "I am going back over here to in-menu sensitivity and increasing it."

    assert normalize_anchor_text("In-menu sensitivity") == "in menu sensitivity"
    assert score_anchor_region(
        region_name="opening",
        transcript_text=text,
        anchors=("in menu sensitivity", "missing phrase"),
    ) == {
        "region": "opening",
        "hits": 1,
        "total": 2,
        "found": {"in menu sensitivity": True, "missing phrase": False},
    }


def test_anchor_scoring_rejects_substrings_and_empty_normalized_anchors() -> None:
    assert score_anchor_region(
        region_name="opening",
        transcript_text="the claimed value",
        anchors=("aim", "!!!"),
    ) == {
        "region": "opening",
        "hits": 0,
        "total": 2,
        "found": {"aim": False, "!!!": False},
    }


def test_detect_repetition_warns_for_repeated_sentence_blocks() -> None:
    repeated = "Alpha beta gamma. " * 8
    normal = "Alpha beta gamma. Delta epsilon zeta. Eta theta iota."

    assert detect_repetition(repeated).has_warning is True
    assert detect_repetition(normal).has_warning is False


def test_detect_repetition_warns_for_short_repeated_word_blocks() -> None:
    assert detect_repetition("Alpha beta gamma " * 4).has_warning is True


def test_detect_repetition_normalizes_case_for_sentence_blocks() -> None:
    text = "Alpha beta gamma. alpha beta gamma. ALPHA beta gamma. Alpha beta gamma."

    assert detect_repetition(text).has_warning is True


def test_pricing_profile_supports_standard_gemini_flash_lite() -> None:
    profile = PricingProfile.for_model("gemini-3.1-flash-lite")

    assert profile.model == "gemini-3.1-flash-lite"
    assert profile.text_image_video_input_per_million == 0.25
    assert profile.audio_input_per_million == 0.50
    assert profile.output_per_million == 1.50


def test_pricing_profile_rejects_unsupported_models() -> None:
    with pytest.raises(ValueError, match="Unsupported pricing profile"):
        PricingProfile.for_model("gemini-3.1-pro")


def test_calculate_cost_uses_aggregate_input_when_modalities_are_absent() -> None:
    profile = PricingProfile.for_model("gemini-3.1-flash-lite")
    usage = TokenUsage(input_tokens=100_000, output_tokens=10_000, total_tokens=110_000)

    cost = calculate_cost(usage, profile)

    assert cost.input_cost_usd == 0.025
    assert cost.output_cost_usd == 0.015
    assert cost.total_cost_usd == 0.04
    assert cost.audio_costing_available is False


def test_calculate_cost_prices_audio_tokens_when_present() -> None:
    profile = PricingProfile.for_model("gemini-3.1-flash-lite")
    usage = TokenUsage(
        input_tokens=100_000,
        output_tokens=10_000,
        total_tokens=110_000,
        video_input_tokens=80_000,
        audio_input_tokens=20_000,
    )

    cost = calculate_cost(usage, profile)

    assert cost.input_cost_usd == 0.03
    assert cost.output_cost_usd == 0.015
    assert cost.total_cost_usd == 0.045
    assert cost.audio_costing_available is True


def test_order_call_results_sorts_by_window_start_time() -> None:
    calls = [
        CallResult(
            window=BenchmarkWindow(start_seconds=100, end_seconds=200),
            elapsed_seconds=1.0,
            transcript_text="second",
            token_usage=TokenUsage(),
        ),
        CallResult(
            window=BenchmarkWindow(start_seconds=0, end_seconds=100),
            elapsed_seconds=1.0,
            transcript_text="first",
            token_usage=TokenUsage(),
        ),
    ]

    ordered = order_call_results(calls)

    assert [call.transcript_text for call in ordered] == ["first", "second"]


def test_aggregate_run_summary_orders_windows_and_sums_metrics() -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=300,
        anchor_regions=(
            AnchorRegion(
                name="opening",
                start_seconds=0,
                end_seconds=300,
                anchors=("hello world",),
            ),
        ),
    )
    combination = BenchmarkCombination(window_seconds=180, overlap_seconds=30)
    calls = [
        CallResult(
            window=BenchmarkWindow(start_seconds=150, end_seconds=300),
            elapsed_seconds=2.0,
            transcript_text="world",
            token_usage=TokenUsage(input_tokens=200, output_tokens=20, total_tokens=220),
        ),
        CallResult(
            window=BenchmarkWindow(start_seconds=0, end_seconds=180),
            elapsed_seconds=1.0,
            transcript_text="hello",
            token_usage=TokenUsage(input_tokens=100, output_tokens=10, total_tokens=110),
        ),
    ]

    summary = aggregate_run_summary(
        video=video,
        combination=combination,
        model="gemini-3.1-flash-lite",
        prompt_variant="plain_transcript_v1",
        media_resolution="LOW",
        output_cap_tokens=900,
        concurrency=2,
        run_number=1,
        wall_clock_seconds=2.2,
        calls=calls,
        pricing=PricingProfile.for_model("gemini-3.1-flash-lite"),
    )

    assert summary["video_id"] == "abc123"
    assert summary["title"] == "Demo"
    assert summary["duration_seconds"] == 300
    assert summary["model"] == "gemini-3.1-flash-lite"
    assert summary["prompt_variant"] == "plain_transcript_v1"
    assert summary["media_resolution"] == "LOW"
    assert summary["combination"] == "180s / 30s"
    assert summary["window_seconds"] == 180
    assert summary["overlap_seconds"] == 30
    assert summary["output_cap_tokens"] == 900
    assert summary["concurrency"] == 2
    assert summary["run_number"] == 1
    assert summary["call_count"] == 2
    assert summary["failed_call_count"] == 0
    assert summary["wall_clock_seconds"] == 2.2
    assert summary["summed_call_latency_seconds"] == 3.0
    assert summary["input_tokens"] == 300
    assert summary["output_tokens"] == 30
    assert summary["total_tokens"] == 330
    assert summary["estimated_cost_usd"] == 0.00012
    assert summary["anchor_score"] == "1/1"
    assert summary["anchor_results"] == [
        {
            "region": "opening",
            "hits": 1,
            "total": 1,
            "found": {"hello world": True},
        }
    ]
    assert summary["repetition_warning"] is False
    assert summary["word_count"] == 2
    assert summary["stitched_transcript"] == "hello\n\nworld"


def test_aggregate_run_summary_preserves_modality_tokens_for_audio_costing() -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=300,
    )
    combination = BenchmarkCombination(window_seconds=150, overlap_seconds=0)
    calls = [
        CallResult(
            window=BenchmarkWindow(start_seconds=0, end_seconds=150),
            elapsed_seconds=1.0,
            transcript_text="hello",
            token_usage=TokenUsage(
                input_tokens=40_000,
                output_tokens=4_000,
                total_tokens=44_000,
                video_input_tokens=30_000,
                audio_input_tokens=10_000,
            ),
        ),
        CallResult(
            window=BenchmarkWindow(start_seconds=150, end_seconds=300),
            elapsed_seconds=1.5,
            transcript_text="world",
            token_usage=TokenUsage(
                input_tokens=60_000,
                output_tokens=6_000,
                total_tokens=66_000,
                video_input_tokens=50_000,
                audio_input_tokens=10_000,
            ),
        ),
    ]

    summary = aggregate_run_summary(
        video=video,
        combination=combination,
        model="gemini-3.1-flash-lite",
        prompt_variant="plain_transcript_v1",
        media_resolution="LOW",
        output_cap_tokens=900,
        concurrency=2,
        run_number=1,
        wall_clock_seconds=2.0,
        calls=calls,
        pricing=PricingProfile.for_model("gemini-3.1-flash-lite"),
    )

    assert summary["video_input_tokens"] == 80_000
    assert summary["audio_input_tokens"] == 20_000
    assert summary["input_cost_usd"] == 0.03
    assert summary["output_cost_usd"] == 0.015
    assert summary["estimated_cost_usd"] == 0.045
    assert summary["audio_costing_available"] is True


def test_aggregate_run_summary_scores_anchors_only_against_overlapping_windows() -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=200,
        anchor_regions=(
            AnchorRegion(
                name="opening",
                start_seconds=0,
                end_seconds=100,
                anchors=("target phrase",),
            ),
        ),
    )
    combination = BenchmarkCombination(window_seconds=100, overlap_seconds=0)
    calls = [
        CallResult(
            window=BenchmarkWindow(start_seconds=0, end_seconds=100),
            elapsed_seconds=1.0,
            transcript_text="intro without the anchor",
            token_usage=TokenUsage(input_tokens=100, output_tokens=10, total_tokens=110),
        ),
        CallResult(
            window=BenchmarkWindow(start_seconds=100, end_seconds=200),
            elapsed_seconds=1.0,
            transcript_text="target phrase appears later",
            token_usage=TokenUsage(input_tokens=100, output_tokens=10, total_tokens=110),
        ),
    ]

    summary = aggregate_run_summary(
        video=video,
        combination=combination,
        model="gemini-3.1-flash-lite",
        prompt_variant="plain_transcript_v1",
        media_resolution="LOW",
        output_cap_tokens=900,
        concurrency=1,
        run_number=1,
        wall_clock_seconds=2.0,
        calls=calls,
        pricing=PricingProfile.for_model("gemini-3.1-flash-lite"),
    )

    assert summary["anchor_score"] == "0/1"
    assert summary["anchor_results"] == [
        {
            "region": "opening",
            "hits": 0,
            "total": 1,
            "found": {"target phrase": False},
        }
    ]


def test_aggregate_run_summary_includes_cost_breakdown_fields() -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=120,
    )

    summary = aggregate_run_summary(
        video=video,
        combination=BenchmarkCombination(window_seconds=120, overlap_seconds=0),
        model="gemini-3.1-flash-lite",
        prompt_variant="plain_transcript_v1",
        media_resolution="LOW",
        output_cap_tokens=900,
        concurrency=1,
        run_number=1,
        wall_clock_seconds=1.0,
        calls=[
            CallResult(
                window=BenchmarkWindow(start_seconds=0, end_seconds=120),
                elapsed_seconds=1.0,
                transcript_text="hello",
                token_usage=TokenUsage(
                    input_tokens=100_000,
                    output_tokens=10_000,
                    total_tokens=110_000,
                ),
            ),
        ],
        pricing=PricingProfile.for_model("gemini-3.1-flash-lite"),
    )

    assert summary["input_cost_usd"] == 0.025
    assert summary["output_cost_usd"] == 0.015
    assert summary["estimated_cost_usd"] == 0.04
    assert summary["audio_costing_available"] is False


def test_load_benchmark_config_defaults_repeat_count_to_three(tmp_path) -> None:
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(
        json.dumps(
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "title": "Demo",
                        "duration": "20:20",
                    }
                ],
                "combinations": ["240:30"],
                "concurrency": [1, 4],
                "output_dir": str(tmp_path / "out"),
            }
        ),
        encoding="utf-8",
    )

    config = load_benchmark_config(config_path)

    assert config.repeat_count == 3
    assert config.videos[0].video_id == "abc123"
    assert config.videos[0].duration_seconds == 1220
    assert config.combinations[0] == BenchmarkCombination(
        window_seconds=240,
        overlap_seconds=30,
    )
    assert config.concurrency_levels == [1, 4]
    assert config.output_dir == tmp_path / "out"


@pytest.mark.parametrize("start", [0, "0"])
def test_load_benchmark_config_accepts_zero_anchor_region_start(
    tmp_path,
    start: int | str,
) -> None:
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(
        json.dumps(
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "title": "Demo",
                        "duration": "20:20",
                        "anchor_regions": [
                            {
                                "name": "opening",
                                "start": start,
                                "end": "0:30",
                                "anchors": ["hello world"],
                            }
                        ],
                    }
                ],
                "combinations": ["240:30"],
            }
        ),
        encoding="utf-8",
    )

    config = load_benchmark_config(config_path)

    assert config.videos[0].anchor_regions[0].start_seconds == 0


@pytest.mark.parametrize(
    ("payload", "message"),
    [
        ({"combinations": ["240:30"]}, "Config must include at least one video"),
        (
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "duration": "20:20",
                    }
                ],
            },
            "Config must include at least one combination",
        ),
        (
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "duration": "20:20",
                    }
                ],
                "combinations": ["240:30"],
                "repeat_count": 0,
            },
            "repeat_count must be positive",
        ),
        (
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "duration": "20:20",
                    }
                ],
                "combinations": ["240/30"],
            },
            "Invalid combination",
        ),
    ],
)
def test_load_benchmark_config_rejects_invalid_config(
    tmp_path,
    payload: dict[str, object],
    message: str,
) -> None:
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(ValueError, match=message):
        load_benchmark_config(config_path)


def test_write_reports_creates_json_markdown_and_csv(tmp_path) -> None:
    output_dir = tmp_path / "reports"
    summaries = [
        {
            "video_id": "abc123",
            "title": "Demo",
            "duration_seconds": 300,
            "model": "gemini-3.1-flash-lite",
            "prompt_variant": "plain_transcript_v1",
            "media_resolution": "LOW",
            "combination": "240s / 30s",
            "window_seconds": 240,
            "overlap_seconds": 30,
            "output_cap_tokens": 1152,
            "concurrency": 1,
            "run_number": 1,
            "call_count": 2,
            "failed_call_count": 0,
            "wall_clock_seconds": 5.0,
            "summed_call_latency_seconds": 8.0,
            "input_tokens": 100,
            "output_tokens": 10,
            "total_tokens": 110,
            "video_input_tokens": 80,
            "audio_input_tokens": 20,
            "input_cost_usd": 0.00002,
            "output_cost_usd": 0.00002,
            "estimated_cost_usd": 0.00004,
            "audio_costing_available": True,
            "anchor_score": "1/1",
            "word_count": 42,
            "repetition_warning": False,
            "stitched_transcript": "hello world",
        }
    ]

    write_reports(output_dir=output_dir, summaries=summaries)

    assert json.loads((output_dir / "summary.json").read_text(encoding="utf-8")) == summaries
    assert (output_dir / "summary.md").read_text(encoding="utf-8").startswith("| Video ID |")
    assert "abc123" in (output_dir / "summary.csv").read_text(encoding="utf-8")


def test_write_reports_escapes_markdown_table_cells(tmp_path) -> None:
    output_dir = tmp_path / "reports"
    summaries = [
        {
            "video_id": "abc123",
            "title": "Demo | Pipe\nTitle",
            "duration_seconds": 300,
            "model": "gemini-3.1-flash-lite",
            "combination": "240s / 30s",
            "concurrency": 1,
            "run_number": 1,
            "call_count": 2,
            "wall_clock_seconds": 5.0,
            "summed_call_latency_seconds": 8.0,
            "input_tokens": 100,
            "output_tokens": 10,
            "total_tokens": 110,
            "estimated_cost_usd": 0.00004,
            "anchor_score": "1/1",
            "word_count": 42,
            "repetition_warning": False,
        }
    ]

    write_reports(output_dir=output_dir, summaries=summaries)

    lines = (output_dir / "summary.md").read_text(encoding="utf-8").splitlines()
    assert len(lines) == 3
    assert "Demo \\| Pipe Title" in lines[2]
