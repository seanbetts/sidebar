"""Tests for backend/scripts/gemini_video_benchmark.py."""

from __future__ import annotations

import json

from scripts.gemini_video_benchmark import main, parse_args


def test_parse_args_accepts_config_and_dry_run() -> None:
    args = parse_args(["--config", "benchmark.json", "--dry-run"])

    assert args.config == "benchmark.json"
    assert args.dry_run is True


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
