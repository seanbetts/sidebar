#!/usr/bin/env python3
"""CLI entry point for Gemini video benchmark runs."""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
import time
from pathlib import Path
from typing import Any, Sequence


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from scripts.gemini_video_benchmarking import (  # noqa: E402
    BenchmarkConfig,
    BenchmarkWindow,
    CallResult,
    PlannedRun,
    PricingProfile,
    TokenUsage,
    aggregate_run_summary,
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


def _format_timestamp(seconds: int) -> str:
    """Format a benchmark offset as MM:SS."""
    minutes, remaining_seconds = divmod(seconds, 60)
    return f"{minutes:02d}:{remaining_seconds:02d}"


def _prompt_for_window(window: BenchmarkWindow) -> str:
    """Build the plain transcript prompt for a clipped video window."""
    return (
        "Transcribe ONLY the spoken audio from "
        f"{_format_timestamp(window.start_seconds)} to "
        f"{_format_timestamp(window.end_seconds)} of this video.\n\n"
        "Rules:\n"
        "- Return plain transcript text only.\n"
        "- Preserve original wording as closely as possible.\n"
        "- Do not summarize.\n"
        "- Do not repeat sentences or paragraphs.\n"
        "- Stop at the end timestamp.\n"
    )


def _usage_from_response(response: Any) -> TokenUsage:
    """Map Gemini usage metadata into benchmark token usage."""
    usage = getattr(response, "usage_metadata", None)
    if usage is None:
        return TokenUsage()
    return TokenUsage(
        input_tokens=int(getattr(usage, "prompt_token_count", 0) or 0),
        output_tokens=int(getattr(usage, "candidates_token_count", 0) or 0),
        total_tokens=int(getattr(usage, "total_token_count", 0) or 0),
        cached_tokens=int(getattr(usage, "cached_content_token_count", 0) or 0),
    )


async def _run_window_call(
    client: Any,
    *,
    model: str,
    video_url: str,
    window: BenchmarkWindow,
) -> CallResult:
    """Run one live Gemini call for a benchmark window."""
    from google.genai import types

    started = time.perf_counter()
    try:
        response = await asyncio.to_thread(
            client.models.generate_content,
            model=model,
            contents=types.Content(
                parts=[
                    types.Part(
                        file_data=types.FileData(file_uri=video_url),
                        video_metadata=types.VideoMetadata(
                            start_offset=f"{window.start_seconds}s",
                            end_offset=f"{window.end_seconds}s",
                        ),
                    ),
                    types.Part(text=_prompt_for_window(window)),
                ],
            ),
            config=types.GenerateContentConfig(
                temperature=0,
                max_output_tokens=calculate_output_cap(
                    duration_seconds=window.duration_seconds,
                ),
                media_resolution=types.MediaResolution.MEDIA_RESOLUTION_LOW,
            ),
        )
        return CallResult(
            window=window,
            elapsed_seconds=time.perf_counter() - started,
            transcript_text=getattr(response, "text", None) or "",
            token_usage=_usage_from_response(response),
        )
    except Exception as exc:
        return CallResult(
            window=window,
            elapsed_seconds=time.perf_counter() - started,
            transcript_text="",
            token_usage=TokenUsage(),
            error=str(exc),
        )


async def _run_planned_run(
    client: Any,
    *,
    config: BenchmarkConfig,
    run: PlannedRun,
    model: str,
) -> dict[str, object]:
    """Run all live window calls for one planned benchmark run."""
    semaphore = asyncio.Semaphore(run.concurrency)

    async def guarded_call(window: BenchmarkWindow) -> CallResult:
        async with semaphore:
            return await _run_window_call(
                client,
                model=model,
                video_url=run.video.url,
                window=window,
            )

    started = time.perf_counter()
    calls = await asyncio.gather(*(guarded_call(window) for window in run.windows))
    wall_clock = time.perf_counter() - started
    return aggregate_run_summary(
        video=run.video,
        combination=run.combination,
        model=model,
        prompt_variant=config.prompt_variant,
        media_resolution=config.media_resolution,
        output_cap_tokens=calculate_output_cap(
            duration_seconds=run.combination.window_seconds,
        ),
        concurrency=run.concurrency,
        run_number=run.run_number,
        wall_clock_seconds=wall_clock,
        calls=list(calls),
        pricing=PricingProfile.for_model(model),
    )


async def _run_live(config: BenchmarkConfig) -> list[dict[str, object]]:
    """Run configured live Gemini benchmark calls."""
    from google import genai

    client = genai.Client(api_key=os.environ["GOOGLE_API_KEY"])
    runs = expand_run_matrix(
        videos=config.videos,
        combinations=config.combinations,
        concurrency_levels=config.concurrency_levels,
        repeat_count=config.repeat_count,
    )
    summaries: list[dict[str, object]] = []
    for model in config.models:
        for run in runs:
            summaries.append(await _run_planned_run(client, config=config, run=run, model=model))
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
        config = load_benchmark_config(config_path)
    except (OSError, ValueError) as exc:
        print(f"Config error: {exc}", file=sys.stderr)
        return EXIT_CONFIG

    if not os.environ.get("GOOGLE_API_KEY"):
        print("Config error: Missing environment variable: GOOGLE_API_KEY", file=sys.stderr)
        return EXIT_CONFIG

    try:
        summaries = asyncio.run(_run_live(config))
        write_reports(output_dir=config.output_dir, summaries=summaries)
    except Exception as exc:
        print(f"Benchmark error: {exc}", file=sys.stderr)
        return EXIT_FAILURE

    print(f"Wrote live benchmark report to {config.output_dir}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
