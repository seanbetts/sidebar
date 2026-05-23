"""Tests for backend/scripts/gemini_video_benchmark.py."""

from __future__ import annotations

import json
import asyncio
from types import SimpleNamespace

from scripts import gemini_video_benchmark
from scripts.gemini_video_benchmark import (
    _call_record_from_result,
    _prompt_for_window,
    _run_live,
    _run_planned_run,
    _usage_from_response,
    main,
    parse_args,
)
from scripts.gemini_video_benchmarking import (
    BenchmarkCombination,
    BenchmarkConfig,
    BenchmarkVideo,
    BenchmarkWindow,
    CallResult,
    PlannedRun,
    TokenUsage,
)


def test_parse_args_accepts_config_and_dry_run() -> None:
    args = parse_args(
        [
            "--config",
            "benchmark.json",
            "--dry-run",
            "--call-timeout",
            "45",
            "--parallel-planned-runs",
            "3",
            "--force",
        ]
    )

    assert args.config == "benchmark.json"
    assert args.dry_run is True
    assert args.call_timeout == 45
    assert args.parallel_planned_runs == 3
    assert args.force is True


def test_prompt_for_window_uses_plain_transcript_rules_with_timestamps() -> None:
    prompt = _prompt_for_window(BenchmarkWindow(start_seconds=65, end_seconds=185))

    assert "01:05 to 03:05" in prompt
    assert "Return plain transcript text only." in prompt
    assert "Do not summarize." in prompt
    assert "Stop at the end timestamp." in prompt


def test_usage_from_response_maps_gemini_usage_metadata() -> None:
    response = SimpleNamespace(
        usage_metadata=SimpleNamespace(
            prompt_token_count=10,
            candidates_token_count=20,
            total_token_count=30,
            cached_content_token_count=4,
        )
    )

    assert _usage_from_response(response) == TokenUsage(
        input_tokens=10,
        output_tokens=20,
        total_tokens=30,
        cached_tokens=4,
    )


def test_usage_from_response_maps_prompt_token_modality_details() -> None:
    response = SimpleNamespace(
        usage_metadata=SimpleNamespace(
            prompt_token_count=100,
            candidates_token_count=20,
            total_token_count=120,
            cached_content_token_count=5,
            prompt_tokens_details=[
                SimpleNamespace(modality="VIDEO", token_count=70),
                SimpleNamespace(modality="AUDIO", token_count=25),
                SimpleNamespace(modality="TEXT", token_count=5),
            ],
        )
    )

    assert _usage_from_response(response) == TokenUsage(
        input_tokens=100,
        output_tokens=20,
        total_tokens=120,
        cached_tokens=5,
        video_input_tokens=70,
        audio_input_tokens=25,
    )


def test_usage_from_response_returns_empty_usage_when_metadata_missing() -> None:
    assert _usage_from_response(SimpleNamespace()) == TokenUsage()


def test_run_planned_run_bounds_concurrency_and_aggregates_in_window_order(
    monkeypatch,
    tmp_path,
) -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=300,
    )
    combination = BenchmarkCombination(window_seconds=100, overlap_seconds=0)
    windows = (
        BenchmarkWindow(start_seconds=0, end_seconds=100),
        BenchmarkWindow(start_seconds=100, end_seconds=200),
        BenchmarkWindow(start_seconds=200, end_seconds=300),
    )
    run = PlannedRun(
        video=video,
        combination=combination,
        concurrency=2,
        run_number=1,
        windows=windows,
    )
    config = BenchmarkConfig(
        videos=[video],
        combinations=[combination],
        concurrency_levels=[2],
        repeat_count=1,
        models=["gemini-3.1-flash-lite"],
        prompt_variant="plain_transcript_v1",
        media_resolution="HIGH",
        output_dir=tmp_path,
    )
    active_count = 0
    max_active_count = 0
    observed_media_resolutions: list[str] = []

    async def fake_run_window_call(
        client,
        *,
        model: str,
        video_url: str,
        window: BenchmarkWindow,
        media_resolution: str,
        call_timeout: float,
    ) -> CallResult:
        nonlocal active_count, max_active_count
        assert model == "gemini-3.1-flash-lite"
        assert video_url == video.url
        assert call_timeout == 120
        observed_media_resolutions.append(media_resolution)
        active_count += 1
        max_active_count = max(max_active_count, active_count)
        await asyncio.sleep((300 - window.start_seconds) / 10_000)
        active_count -= 1
        transcript = {
            0: "first",
            100: "second",
            200: "third",
        }[window.start_seconds]
        return CallResult(
            window=window,
            elapsed_seconds=0.1,
            transcript_text=transcript,
            token_usage=TokenUsage(input_tokens=1, output_tokens=1, total_tokens=2),
        )

    monkeypatch.setattr(
        gemini_video_benchmark,
        "_run_window_call",
        fake_run_window_call,
    )

    summary = asyncio.run(
        _run_planned_run(
            object(),
            config=config,
            run=run,
            model="gemini-3.1-flash-lite",
            call_timeout=120,
        )
    )

    assert max_active_count == 2
    assert observed_media_resolutions == ["HIGH", "HIGH", "HIGH"]
    assert summary["media_resolution"] == "HIGH"
    assert summary["stitched_transcript"] == "first\n\nsecond\n\nthird"


def test_call_record_from_result_includes_resume_key_and_cost(tmp_path) -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=300,
    )
    combination = BenchmarkCombination(window_seconds=100, overlap_seconds=10)
    run = PlannedRun(
        video=video,
        combination=combination,
        concurrency=2,
        run_number=3,
        windows=(BenchmarkWindow(start_seconds=0, end_seconds=100),),
    )
    result = CallResult(
        window=BenchmarkWindow(start_seconds=0, end_seconds=100),
        elapsed_seconds=1.25,
        transcript_text="hello world",
        token_usage=TokenUsage(
            input_tokens=1000,
            output_tokens=200,
            total_tokens=1200,
            video_input_tokens=900,
        ),
    )

    record = _call_record_from_result(
        config=BenchmarkConfig(
            videos=[video],
            combinations=[combination],
            concurrency_levels=[2],
            repeat_count=1,
            models=["gemini-3.1-flash-lite"],
            prompt_variant="plain_transcript_v1",
            media_resolution="LOW",
            output_dir=tmp_path,
        ),
        run=run,
        model="gemini-3.1-flash-lite",
        result=result,
    )

    assert record["video_id"] == "abc123"
    assert record["run_number"] == 3
    assert record["window_start_seconds"] == 0
    assert record["window_end_seconds"] == 100
    assert record["input_tokens"] == 1000
    assert record["estimated_cost_usd"] > 0
    assert record["transcript_text"] == "hello world"


def test_run_live_writes_window_records_and_skips_completed_calls(
    monkeypatch,
    tmp_path,
) -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=200,
    )
    combination = BenchmarkCombination(window_seconds=100, overlap_seconds=0)
    config = BenchmarkConfig(
        videos=[video],
        combinations=[combination],
        concurrency_levels=[1],
        repeat_count=1,
        models=["gemini-3.1-flash-lite"],
        prompt_variant="plain_transcript_v1",
        media_resolution="LOW",
        output_dir=tmp_path,
    )
    calls_jsonl = tmp_path / "calls.jsonl"
    existing = _call_record_from_result(
        config=config,
        run=PlannedRun(
            video=video,
            combination=combination,
            concurrency=1,
            run_number=1,
            windows=(BenchmarkWindow(start_seconds=0, end_seconds=100),),
        ),
        model="gemini-3.1-flash-lite",
        result=CallResult(
            window=BenchmarkWindow(start_seconds=0, end_seconds=100),
            elapsed_seconds=0.5,
            transcript_text="cached first",
            token_usage=TokenUsage(input_tokens=10, output_tokens=5, total_tokens=15),
        ),
    )
    calls_jsonl.write_text(json.dumps(existing) + "\n", encoding="utf-8")
    observed_windows: list[int] = []

    async def fake_run_window_call(
        client,
        *,
        model: str,
        video_url: str,
        window: BenchmarkWindow,
        media_resolution: str,
        call_timeout: float,
    ) -> CallResult:
        observed_windows.append(window.start_seconds)
        return CallResult(
            window=window,
            elapsed_seconds=0.25,
            transcript_text="live second",
            token_usage=TokenUsage(input_tokens=20, output_tokens=10, total_tokens=30),
        )

    monkeypatch.setattr(
        gemini_video_benchmark,
        "_run_window_call",
        fake_run_window_call,
    )

    summaries = asyncio.run(
        _run_live(
            config,
            client=object(),
            call_timeout=30,
            parallel_planned_runs=1,
            force=False,
            progress=False,
        )
    )

    records = [
        json.loads(line)
        for line in calls_jsonl.read_text(encoding="utf-8").splitlines()
    ]
    assert observed_windows == [100]
    assert len(records) == 2
    assert summaries[0]["stitched_transcript"] == "cached first\n\nlive second"


def test_run_live_can_parallelize_planned_runs(monkeypatch, tmp_path) -> None:
    video = BenchmarkVideo(
        video_id="abc123",
        url="https://youtu.be/abc123",
        title="Demo",
        duration_seconds=100,
    )
    combination = BenchmarkCombination(window_seconds=100, overlap_seconds=0)
    config = BenchmarkConfig(
        videos=[video],
        combinations=[combination],
        concurrency_levels=[1],
        repeat_count=3,
        models=["gemini-3.1-flash-lite"],
        prompt_variant="plain_transcript_v1",
        media_resolution="LOW",
        output_dir=tmp_path,
    )
    active_count = 0
    max_active_count = 0

    async def fake_run_window_call(
        client,
        *,
        model: str,
        video_url: str,
        window: BenchmarkWindow,
        media_resolution: str,
        call_timeout: float,
    ) -> CallResult:
        nonlocal active_count, max_active_count
        active_count += 1
        max_active_count = max(max_active_count, active_count)
        await asyncio.sleep(0.01)
        active_count -= 1
        return CallResult(
            window=window,
            elapsed_seconds=0.01,
            transcript_text=f"run window {window.start_seconds}",
            token_usage=TokenUsage(input_tokens=1, output_tokens=1, total_tokens=2),
        )

    monkeypatch.setattr(
        gemini_video_benchmark,
        "_run_window_call",
        fake_run_window_call,
    )

    summaries = asyncio.run(
        _run_live(
            config,
            client=object(),
            call_timeout=30,
            parallel_planned_runs=2,
            force=True,
            progress=False,
        )
    )

    assert len(summaries) == 3
    assert max_active_count == 2


def test_main_dry_run_writes_summary_reports_without_google_api_key(
    monkeypatch,
    tmp_path,
) -> None:
    monkeypatch.setenv("GOOGLE_API_KEY", "")
    output_dir = tmp_path / "reports"
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(
        json.dumps(
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "title": "Demo",
                        "duration": "3:00",
                    }
                ],
                "combinations": ["120:30"],
                "concurrency": [1],
                "repeat_count": 1,
                "models": ["gemini-3.1-flash-lite"],
                "output_dir": str(output_dir),
            }
        ),
        encoding="utf-8",
    )

    exit_code = main(["--config", str(config_path), "--dry-run"])

    assert exit_code == 0
    assert (output_dir / "summary.csv").exists()
    assert (output_dir / "summary.md").exists()
    summary = json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))
    assert summary[0]["video_id"] == "abc123"
    assert summary[0]["mode"] == "dry-run"


def test_main_live_runs_stubbed_benchmark_and_writes_reports(
    monkeypatch,
    tmp_path,
    capsys,
) -> None:
    output_dir = tmp_path / "reports"
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(
        json.dumps(
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "title": "Demo",
                        "duration": "3:00",
                    }
                ],
                "combinations": ["120:30"],
                "models": ["gemini-3.1-flash-lite"],
                "output_dir": str(output_dir),
            }
        ),
        encoding="utf-8",
    )

    async def fake_run_live(
        config,
        *,
        call_timeout: float,
        parallel_planned_runs: int,
        force: bool,
        progress: bool,
    ):
        assert config.output_dir == output_dir
        assert call_timeout == 120.0
        assert parallel_planned_runs == 1
        assert force is False
        assert progress is True
        return [{"video_id": "abc123", "mode": "live"}]

    monkeypatch.setenv("GOOGLE_API_KEY", "test-key")
    monkeypatch.setattr(gemini_video_benchmark, "_run_live", fake_run_live)

    exit_code = main(["--config", str(config_path)])

    assert exit_code == 0
    assert json.loads((output_dir / "summary.json").read_text(encoding="utf-8")) == [
        {"video_id": "abc123", "mode": "live"}
    ]
    assert f"Wrote live benchmark report to {output_dir}" in capsys.readouterr().out


def test_main_live_without_google_api_key_exits_config_error(
    monkeypatch,
    tmp_path,
    capsys,
) -> None:
    monkeypatch.setenv("GOOGLE_API_KEY", "")
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(
        json.dumps(
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "title": "Demo",
                        "duration": "3:00",
                    }
                ],
                "combinations": ["120:30"],
            }
        ),
        encoding="utf-8",
    )

    exit_code = main(["--config", str(config_path)])

    assert exit_code == 2
    assert "Missing environment variable: GOOGLE_API_KEY" in capsys.readouterr().err


def test_main_dry_run_with_missing_video_duration_exits_config_error(
    tmp_path,
    capsys,
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
                    }
                ],
                "combinations": ["120:30"],
            }
        ),
        encoding="utf-8",
    )

    exit_code = main(["--config", str(config_path), "--dry-run"])

    assert exit_code == 2
    captured = capsys.readouterr()
    assert "Config error:" in captured.err
    assert "duration" in captured.err


def test_main_dry_run_with_top_level_list_exits_config_error(
    tmp_path,
    capsys,
) -> None:
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(json.dumps([]), encoding="utf-8")

    exit_code = main(["--config", str(config_path), "--dry-run"])

    assert exit_code == 2
    captured = capsys.readouterr()
    assert "Config error:" in captured.err
    assert "top-level object" in captured.err


def test_main_dry_run_with_null_video_duration_exits_config_error(
    tmp_path,
    capsys,
) -> None:
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(
        json.dumps(
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "duration": None,
                    }
                ],
                "combinations": ["120:30"],
            }
        ),
        encoding="utf-8",
    )

    exit_code = main(["--config", str(config_path), "--dry-run"])

    assert exit_code == 2
    captured = capsys.readouterr()
    assert "Config error:" in captured.err
    assert "duration" in captured.err


def test_main_dry_run_with_null_anchor_regions_exits_config_error(
    tmp_path,
    capsys,
) -> None:
    config_path = tmp_path / "benchmark.json"
    config_path.write_text(
        json.dumps(
            {
                "videos": [
                    {
                        "video_id": "abc123",
                        "url": "https://youtu.be/abc123",
                        "duration": "3:00",
                        "anchor_regions": None,
                    }
                ],
                "combinations": ["120:30"],
            }
        ),
        encoding="utf-8",
    )

    exit_code = main(["--config", str(config_path), "--dry-run"])

    assert exit_code == 2
    captured = capsys.readouterr()
    assert "Config error:" in captured.err
    assert "anchor_regions" in captured.err
