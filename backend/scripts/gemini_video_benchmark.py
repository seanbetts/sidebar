#!/usr/bin/env python3
"""CLI entry point for Gemini video benchmark runs."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Sequence


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from scripts.gemini_video_benchmarking import (  # noqa: E402
    calculate_output_cap,
    expand_run_matrix,
    load_benchmark_config,
    write_reports,
)
from scripts.ops_diagnostics_common import EXIT_CONFIG, EXIT_FAILURE, EXIT_OK, load_local_env  # noqa: E402


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(description="Run Gemini video benchmark plans.")
    parser.add_argument("--config", required=True, help="Path to benchmark JSON config.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Write planned benchmark reports without live Gemini calls.",
    )
    return parser.parse_args(argv)


def _dry_run_summaries(config_path: Path) -> list[dict[str, object]]:
    """Build deterministic dry-run summary rows for a benchmark config."""
    config = load_benchmark_config(config_path)
    runs = expand_run_matrix(
        videos=config.videos,
        combinations=config.combinations,
        concurrency_levels=config.concurrency_levels,
        repeat_count=config.repeat_count,
    )
    summaries: list[dict[str, object]] = []
    for model in config.models:
        for run in runs:
            summaries.append(
                {
                    "mode": "dry-run",
                    "video_id": run.video.video_id,
                    "title": run.video.title,
                    "duration_seconds": run.video.duration_seconds,
                    "model": model,
                    "models": ", ".join(config.models),
                    "prompt_variant": config.prompt_variant,
                    "media_resolution": config.media_resolution,
                    "combination": run.combination.label,
                    "window_seconds": run.combination.window_seconds,
                    "overlap_seconds": run.combination.overlap_seconds,
                    "output_cap_tokens": calculate_output_cap(
                        duration_seconds=run.combination.window_seconds,
                    ),
                    "concurrency": run.concurrency,
                    "run_number": run.run_number,
                    "call_count": len(run.windows),
                    "failed_call_count": 0,
                    "wall_clock_seconds": 0,
                    "summed_call_latency_seconds": 0,
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "total_tokens": 0,
                    "video_input_tokens": None,
                    "audio_input_tokens": None,
                    "input_cost_usd": 0,
                    "output_cost_usd": 0,
                    "estimated_cost_usd": 0,
                    "audio_costing_available": False,
                    "anchor_score": "0/0",
                    "word_count": 0,
                    "repetition_warning": False,
                }
            )
    write_reports(output_dir=config.output_dir, summaries=summaries)
    return summaries


def main(argv: Sequence[str] | None = None) -> int:
    """Run the Gemini video benchmark CLI."""
    args = parse_args(argv)
    load_local_env()
    config_path = Path(args.config)

    try:
        if args.dry_run:
            _dry_run_summaries(config_path)
            return EXIT_OK
        load_benchmark_config(config_path)
    except (OSError, ValueError) as exc:
        print(f"Config error: {exc}", file=sys.stderr)
        return EXIT_CONFIG

    if not os.environ.get("GOOGLE_API_KEY"):
        print("Config error: Missing environment variable: GOOGLE_API_KEY", file=sys.stderr)
        return EXIT_CONFIG

    print("Live execution is added in the next task.")
    return EXIT_FAILURE


if __name__ == "__main__":
    raise SystemExit(main())
