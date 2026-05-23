"""Tests for backend/scripts/gemini_video_benchmark.py."""

from __future__ import annotations

import json
from types import SimpleNamespace

from scripts import gemini_video_benchmark
from scripts.gemini_video_benchmark import (
    _prompt_for_window,
    _usage_from_response,
    main,
    parse_args,
)
from scripts.gemini_video_benchmarking import BenchmarkWindow, TokenUsage


def test_parse_args_accepts_config_and_dry_run() -> None:
    args = parse_args(["--config", "benchmark.json", "--dry-run"])

    assert args.config == "benchmark.json"
    assert args.dry_run is True


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


def test_usage_from_response_returns_empty_usage_when_metadata_missing() -> None:
    assert _usage_from_response(SimpleNamespace()) == TokenUsage()


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

    async def fake_run_live(config):
        assert config.output_dir == output_dir
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
