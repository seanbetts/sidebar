#!/usr/bin/env python3
"""CLI entry point for Gemini video benchmark runs."""

from __future__ import annotations

import argparse
import asyncio
import json
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
    parser.add_argument(
        "--call-timeout",
        type=float,
        default=120.0,
        help="Maximum seconds to wait for one Gemini window call.",
    )
    parser.add_argument(
        "--parallel-planned-runs",
        type=int,
        default=1,
        help="Number of planned benchmark rows to run concurrently.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Ignore existing calls.jsonl records and rerun every window.",
    )
    parser.add_argument(
        "--no-progress",
        action="store_true",
        help="Disable per-window progress logging.",
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
    video_tokens, audio_tokens = _prompt_modality_token_counts(usage)
    return TokenUsage(
        input_tokens=int(getattr(usage, "prompt_token_count", 0) or 0),
        output_tokens=int(getattr(usage, "candidates_token_count", 0) or 0),
        total_tokens=int(getattr(usage, "total_token_count", 0) or 0),
        cached_tokens=int(getattr(usage, "cached_content_token_count", 0) or 0),
        video_input_tokens=video_tokens,
        audio_input_tokens=audio_tokens,
    )


def _prompt_modality_token_counts(usage: Any) -> tuple[int | None, int | None]:
    """Return video and audio prompt token counts when Gemini exposes them."""
    video_tokens = 0
    audio_tokens = 0
    has_video_tokens = False
    has_audio_tokens = False
    for detail in getattr(usage, "prompt_tokens_details", None) or ():
        modality = _modality_name(getattr(detail, "modality", ""))
        token_count = int(getattr(detail, "token_count", 0) or 0)
        if modality == "VIDEO":
            video_tokens += token_count
            has_video_tokens = True
        elif modality == "AUDIO":
            audio_tokens += token_count
            has_audio_tokens = True
    return (
        video_tokens if has_video_tokens else None,
        audio_tokens if has_audio_tokens else None,
    )


def _modality_name(value: Any) -> str:
    """Normalize SDK modality values without depending on SDK classes."""
    raw = getattr(value, "name", None) or getattr(value, "value", None) or str(value)
    return str(raw).upper().removeprefix("MODALITY_")


def _media_resolution_enum(types: Any, media_resolution: str) -> Any:
    """Map config media resolution text to the Gemini SDK enum value."""
    normalized = media_resolution.strip().upper()
    enum_name = f"MEDIA_RESOLUTION_{normalized}"
    if normalized not in {"LOW", "MEDIUM", "HIGH"}:
        raise ValueError(f"Unsupported media_resolution: {media_resolution}")
    if hasattr(types.MediaResolution, enum_name):
        return getattr(types.MediaResolution, enum_name)
    if hasattr(types.MediaResolution, normalized):
        return getattr(types.MediaResolution, normalized)
    raise ValueError(f"Unsupported media_resolution: {media_resolution}")


async def _run_window_call(
    client: Any,
    *,
    model: str,
    video_url: str,
    window: BenchmarkWindow,
    media_resolution: str,
    call_timeout: float,
) -> CallResult:
    """Run one live Gemini call for a benchmark window."""
    from google.genai import types

    started = time.perf_counter()
    try:
        response = await asyncio.wait_for(
            asyncio.to_thread(
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
                    media_resolution=_media_resolution_enum(types, media_resolution),
                ),
            ),
            timeout=call_timeout,
        )
        return CallResult(
            window=window,
            elapsed_seconds=time.perf_counter() - started,
            transcript_text=getattr(response, "text", None) or "",
            token_usage=_usage_from_response(response),
        )
    except asyncio.TimeoutError:
        return CallResult(
            window=window,
            elapsed_seconds=time.perf_counter() - started,
            transcript_text="",
            token_usage=TokenUsage(),
            error=f"Timed out after {call_timeout:g}s",
        )
    except Exception as exc:
        return CallResult(
            window=window,
            elapsed_seconds=time.perf_counter() - started,
            transcript_text="",
            token_usage=TokenUsage(),
            error=str(exc),
        )


def _call_record_key(
    *,
    config: BenchmarkConfig,
    run: PlannedRun,
    model: str,
    window: BenchmarkWindow,
) -> tuple[object, ...]:
    """Return the stable identity for a benchmark window call."""
    return (
        run.video.video_id,
        model,
        config.prompt_variant,
        config.media_resolution,
        run.combination.window_seconds,
        run.combination.overlap_seconds,
        run.concurrency,
        run.run_number,
        window.start_seconds,
        window.end_seconds,
    )


def _call_record_key_from_record(record: dict[str, object]) -> tuple[object, ...]:
    """Return the stable identity from a persisted window call record."""
    return (
        record["video_id"],
        record["model"],
        record["prompt_variant"],
        record["media_resolution"],
        record["window_seconds"],
        record["overlap_seconds"],
        record["concurrency"],
        record["run_number"],
        record["window_start_seconds"],
        record["window_end_seconds"],
    )


def _call_record_from_result(
    *,
    config: BenchmarkConfig,
    run: PlannedRun,
    model: str,
    result: CallResult,
) -> dict[str, object]:
    """Build one append-only JSONL record from a window call result."""
    cost = PricingProfile.for_model(model)
    call_cost = aggregate_run_summary(
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
        wall_clock_seconds=result.elapsed_seconds,
        calls=[result],
        pricing=cost,
    )
    return {
        "video_id": run.video.video_id,
        "title": run.video.title,
        "duration_seconds": run.video.duration_seconds,
        "model": model,
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
        "window_start_seconds": result.window.start_seconds,
        "window_end_seconds": result.window.end_seconds,
        "elapsed_seconds": round(result.elapsed_seconds, 3),
        "input_tokens": result.token_usage.input_tokens,
        "output_tokens": result.token_usage.output_tokens,
        "total_tokens": result.token_usage.total_tokens,
        "cached_tokens": result.token_usage.cached_tokens,
        "video_input_tokens": result.token_usage.video_input_tokens,
        "audio_input_tokens": result.token_usage.audio_input_tokens,
        "input_cost_usd": call_cost["input_cost_usd"],
        "output_cost_usd": call_cost["output_cost_usd"],
        "estimated_cost_usd": call_cost["estimated_cost_usd"],
        "audio_costing_available": call_cost["audio_costing_available"],
        "error": result.error,
        "transcript_text": result.transcript_text,
    }


def _call_result_from_record(record: dict[str, object]) -> CallResult:
    """Reconstruct a call result from one persisted JSONL record."""
    return CallResult(
        window=BenchmarkWindow(
            start_seconds=_record_int(record, "window_start_seconds"),
            end_seconds=_record_int(record, "window_end_seconds"),
        ),
        elapsed_seconds=_record_float(record, "elapsed_seconds"),
        transcript_text=str(record.get("transcript_text") or ""),
        token_usage=TokenUsage(
            input_tokens=_record_int(record, "input_tokens", default=0),
            output_tokens=_record_int(record, "output_tokens", default=0),
            total_tokens=_record_int(record, "total_tokens", default=0),
            cached_tokens=_record_int(record, "cached_tokens", default=0),
            video_input_tokens=_record_optional_int(record, "video_input_tokens"),
            audio_input_tokens=_record_optional_int(record, "audio_input_tokens"),
        ),
        error=(str(record["error"]) if record.get("error") else None),
    )


def _record_int(record: dict[str, object], key: str, *, default: int | None = None) -> int:
    """Return one JSON record field as an int."""
    value = record.get(key, default)
    if value is None:
        raise ValueError(f"Missing call record field: {key}")
    return int(str(value))


def _record_optional_int(record: dict[str, object], key: str) -> int | None:
    """Return one optional JSON record field as an int."""
    value = record.get(key)
    if value is None:
        return None
    return int(str(value))


def _record_float(record: dict[str, object], key: str) -> float:
    """Return one JSON record field as a float."""
    value = record.get(key)
    if value is None:
        raise ValueError(f"Missing call record field: {key}")
    return float(str(value))


def _load_call_records(output_dir: Path) -> dict[tuple[object, ...], dict[str, object]]:
    """Load existing per-window call records for resume support."""
    calls_path = output_dir / "calls.jsonl"
    if not calls_path.exists():
        return {}
    records: dict[tuple[object, ...], dict[str, object]] = {}
    for line in calls_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        records[_call_record_key_from_record(record)] = record
    return records


def _append_call_record(output_dir: Path, record: dict[str, object]) -> None:
    """Append one durable per-window call record."""
    output_dir.mkdir(parents=True, exist_ok=True)
    with (output_dir / "calls.jsonl").open("a", encoding="utf-8") as file:
        file.write(json.dumps(record, sort_keys=True) + "\n")


async def _run_planned_run(
    client: Any,
    *,
    config: BenchmarkConfig,
    run: PlannedRun,
    model: str,
    call_timeout: float,
    completed_records: dict[tuple[object, ...], dict[str, object]] | None = None,
    record_lock: asyncio.Lock | None = None,
    force: bool = False,
    progress: bool = False,
    progress_state: dict[str, int] | None = None,
) -> dict[str, object]:
    """Run all live window calls for one planned benchmark run."""
    semaphore = asyncio.Semaphore(run.concurrency)
    completed_records = completed_records if completed_records is not None else {}
    record_lock = record_lock or asyncio.Lock()

    async def guarded_call(window: BenchmarkWindow) -> CallResult:
        key = _call_record_key(config=config, run=run, model=model, window=window)
        if not force and key in completed_records:
            result = _call_result_from_record(completed_records[key])
            _log_progress(
                run=run,
                model=model,
                result=result,
                skipped=True,
                progress=progress,
                progress_state=progress_state,
            )
            return result
        async with semaphore:
            result = await _run_window_call(
                client,
                model=model,
                video_url=run.video.url,
                window=window,
                media_resolution=config.media_resolution,
                call_timeout=call_timeout,
            )
        record = _call_record_from_result(
            config=config,
            run=run,
            model=model,
            result=result,
        )
        async with record_lock:
            _append_call_record(config.output_dir, record)
            completed_records[key] = record
        _log_progress(
            run=run,
            model=model,
            result=result,
            skipped=False,
            progress=progress,
            progress_state=progress_state,
        )
        return result

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


def _log_progress(
    *,
    run: PlannedRun,
    model: str,
    result: CallResult,
    skipped: bool,
    progress: bool,
    progress_state: dict[str, int] | None,
) -> None:
    """Print one concise progress line for a completed or skipped window."""
    if not progress:
        return
    if progress_state is not None:
        progress_state["completed"] += 1
        prefix = f"[{progress_state['completed']}/{progress_state['total']}]"
    else:
        prefix = "[?/?]"
    status = "skip" if skipped else ("error" if result.error else "ok")
    print(
        f"{prefix} {run.video.video_id} {model} {run.combination.label} "
        f"run {run.run_number} "
        f"{_format_timestamp(result.window.start_seconds)}-"
        f"{_format_timestamp(result.window.end_seconds)} {status} "
        f"{result.elapsed_seconds:.2f}s",
        flush=True,
    )


async def _run_live(
    config: BenchmarkConfig,
    *,
    client: Any | None = None,
    call_timeout: float = 120.0,
    parallel_planned_runs: int = 1,
    force: bool = False,
    progress: bool = True,
) -> list[dict[str, object]]:
    """Run configured live Gemini benchmark calls."""
    if parallel_planned_runs <= 0:
        raise ValueError("parallel_planned_runs must be positive")
    if call_timeout <= 0:
        raise ValueError("call_timeout must be positive")

    if client is None:
        from google import genai

        client = genai.Client(api_key=os.environ["GOOGLE_API_KEY"])
    runs = expand_run_matrix(
        videos=config.videos,
        combinations=config.combinations,
        concurrency_levels=config.concurrency_levels,
        repeat_count=config.repeat_count,
    )
    planned = [
        (model, run)
        for model in config.models
        for run in runs
    ]
    completed_records = {} if force else _load_call_records(config.output_dir)
    record_lock = asyncio.Lock()
    run_semaphore = asyncio.Semaphore(parallel_planned_runs)
    progress_state = {
        "completed": 0,
        "total": sum(len(run.windows) for _, run in planned),
    }

    async def guarded_run(index: int, model: str, run: PlannedRun) -> tuple[int, dict[str, object]]:
        async with run_semaphore:
            summary = await _run_planned_run(
                client,
                config=config,
                run=run,
                model=model,
                call_timeout=call_timeout,
                completed_records=completed_records,
                record_lock=record_lock,
                force=force,
                progress=progress,
                progress_state=progress_state,
            )
            return index, summary

    completed_summaries: list[tuple[int, dict[str, object]]] = []
    tasks = [
        asyncio.create_task(guarded_run(index, model, run))
        for index, (model, run) in enumerate(planned)
    ]
    for task in asyncio.as_completed(tasks):
        completed_summaries.append(await task)
        write_reports(
            output_dir=config.output_dir,
            summaries=[item for _, item in sorted(completed_summaries)],
        )
    return [summary for _, summary in sorted(completed_summaries)]


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
        summaries = asyncio.run(
            _run_live(
                config,
                call_timeout=args.call_timeout,
                parallel_planned_runs=args.parallel_planned_runs,
                force=args.force,
                progress=not args.no_progress,
            )
        )
        write_reports(output_dir=config.output_dir, summaries=summaries)
    except Exception as exc:
        print(f"Benchmark error: {exc}", file=sys.stderr)
        return EXIT_FAILURE

    print(f"Wrote live benchmark report to {config.output_dir}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
