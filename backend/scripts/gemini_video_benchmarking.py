#!/usr/bin/env python3
"""Deterministic helpers for Gemini video benchmark runs."""

from __future__ import annotations

import csv
import json
import re
from collections.abc import Mapping
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any


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
class BenchmarkConfig:
    """Loaded benchmark configuration."""

    videos: list[BenchmarkVideo]
    combinations: list["BenchmarkCombination"]
    concurrency_levels: list[int]
    repeat_count: int
    models: list[str]
    prompt_variant: str
    media_resolution: str
    output_dir: Path


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


@dataclass(frozen=True)
class RepetitionResult:
    """Repetition warning result for a transcript fragment."""

    has_warning: bool
    repeated_text: str | None = None
    repeat_count: int = 0


@dataclass(frozen=True)
class TokenUsage:
    """Token usage returned by Gemini."""

    input_tokens: int = 0
    output_tokens: int = 0
    total_tokens: int = 0
    cached_tokens: int = 0
    video_input_tokens: int | None = None
    audio_input_tokens: int | None = None


@dataclass(frozen=True)
class PricingProfile:
    """Per-million-token pricing for one model."""

    model: str
    text_image_video_input_per_million: float
    audio_input_per_million: float
    output_per_million: float

    @classmethod
    def for_model(cls, model: str) -> "PricingProfile":
        """Return built-in pricing for a supported model."""
        if model != "gemini-3.1-flash-lite":
            raise ValueError(f"Unsupported pricing profile: {model}")
        return cls(
            model=model,
            text_image_video_input_per_million=0.25,
            audio_input_per_million=0.50,
            output_per_million=1.50,
        )


@dataclass(frozen=True)
class CostBreakdown:
    """Estimated cost for one token usage payload."""

    input_cost_usd: float
    output_cost_usd: float
    total_cost_usd: float
    audio_costing_available: bool


@dataclass(frozen=True)
class CallResult:
    """Result from one benchmark window call."""

    window: BenchmarkWindow
    elapsed_seconds: float
    transcript_text: str
    token_usage: TokenUsage
    error: str | None = None


SUMMARY_COLUMNS = [
    "video_id",
    "title",
    "duration_seconds",
    "model",
    "prompt_variant",
    "media_resolution",
    "combination",
    "window_seconds",
    "overlap_seconds",
    "output_cap_tokens",
    "concurrency",
    "run_number",
    "call_count",
    "failed_call_count",
    "wall_clock_seconds",
    "summed_call_latency_seconds",
    "input_tokens",
    "output_tokens",
    "total_tokens",
    "video_input_tokens",
    "audio_input_tokens",
    "input_cost_usd",
    "output_cost_usd",
    "estimated_cost_usd",
    "audio_costing_available",
    "anchor_score",
    "word_count",
    "repetition_warning",
]


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


def parse_offset_seconds(value: str | int) -> int:
    """Parse a non-negative offset from seconds, MM:SS, or HH:MM:SS."""
    if isinstance(value, int):
        if value < 0:
            raise ValueError("Invalid offset: must be non-negative")
        return value

    parts = value.strip().split(":")
    if len(parts) not in {1, 2, 3}:
        raise ValueError(f"Invalid offset: {value}")
    if not all(part.isdigit() for part in parts):
        raise ValueError(f"Invalid offset: {value}")

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
        total < 0
        or (len(numbers) > 1 and seconds >= 60)
        or (len(numbers) == 3 and minutes >= 60)
    ):
        raise ValueError(f"Invalid offset: {value}")
    return total


def _parse_combination(raw: str) -> BenchmarkCombination:
    """Parse a window:overlap combination."""
    parts = raw.split(":", 1)
    if len(parts) != 2 or not all(part.strip().isdigit() for part in parts):
        raise ValueError(f"Invalid combination: {raw}")

    combination = BenchmarkCombination(
        window_seconds=int(parts[0]),
        overlap_seconds=int(parts[1]),
    )
    if combination.window_seconds <= 0:
        raise ValueError("Invalid combination: window must be positive")
    if combination.overlap_seconds < 0:
        raise ValueError("Invalid combination: overlap must be non-negative")
    if combination.overlap_seconds >= combination.window_seconds:
        raise ValueError("Invalid combination: overlap must be less than window")
    return combination


def _require_mapping(value: Any, label: str) -> Mapping[str, Any]:
    """Return a config mapping or raise a clear validation error."""
    if not isinstance(value, Mapping):
        if label == "top-level":
            raise ValueError("Config must be a top-level object")
        raise ValueError(f"Config {label} must be an object")
    return value


def _required_field(item: Mapping[str, Any], field: str, label: str) -> Any:
    """Return a required config field or raise a clear validation error."""
    if field not in item:
        raise ValueError(f"Config {label} must include {field}")
    return item[field]


def _parse_anchor_region(raw: Any, index: int) -> AnchorRegion:
    """Parse one anchor region from config JSON."""
    region = _require_mapping(raw, f"anchor region {index}")
    return AnchorRegion(
        name=str(_required_field(region, "name", f"anchor region {index}")),
        start_seconds=parse_offset_seconds(
            _required_field(region, "start", f"anchor region {index}"),
        ),
        end_seconds=parse_offset_seconds(
            _required_field(region, "end", f"anchor region {index}"),
        ),
        anchors=tuple(
            str(anchor)
            for anchor in _required_field(region, "anchors", f"anchor region {index}")
        ),
    )


def _parse_video(raw: Any, index: int) -> BenchmarkVideo:
    """Parse one benchmark video from config JSON."""
    item = _require_mapping(raw, f"video {index}")
    video_id = str(_required_field(item, "video_id", f"video {index}"))
    return BenchmarkVideo(
        video_id=video_id,
        url=str(_required_field(item, "url", f"video {index}")),
        title=str(item.get("title") or video_id),
        duration_seconds=parse_duration_seconds(
            _required_field(item, "duration", f"video {index}"),
        ),
        anchor_regions=tuple(
            _parse_anchor_region(region, region_index)
            for region_index, region in enumerate(item.get("anchor_regions", []), start=1)
        ),
        reference_transcript_path=(
            str(item["reference_transcript_path"])
            if item.get("reference_transcript_path") is not None
            else None
        ),
    )


def load_benchmark_config(path: Path) -> BenchmarkConfig:
    """Load benchmark config from a JSON file."""
    raw = _require_mapping(json.loads(path.read_text(encoding="utf-8")), "top-level")

    videos = [
        _parse_video(item, index)
        for index, item in enumerate(raw.get("videos", []), start=1)
    ]
    if not videos:
        raise ValueError("Config must include at least one video")

    combinations = [_parse_combination(str(item)) for item in raw.get("combinations", [])]
    if not combinations:
        raise ValueError("Config must include at least one combination")

    concurrency_levels = [int(item) for item in raw.get("concurrency", [1])]
    if any(level <= 0 for level in concurrency_levels):
        raise ValueError("concurrency levels must be positive")

    repeat_count = int(raw.get("repeat_count", 3))
    if repeat_count <= 0:
        raise ValueError("repeat_count must be positive")

    return BenchmarkConfig(
        videos=videos,
        combinations=combinations,
        concurrency_levels=concurrency_levels,
        repeat_count=repeat_count,
        models=[str(item) for item in raw.get("models", ["gemini-3.1-flash-lite"])],
        prompt_variant=str(raw.get("prompt_variant", "plain_transcript_v1")),
        media_resolution=str(raw.get("media_resolution", "LOW")),
        output_dir=Path(raw.get("output_dir", "gemini-video-benchmark-output")),
    )


def calculate_output_cap(
    *,
    duration_seconds: int,
    min_tokens: int = 900,
    tokens_per_second: float = 4.8,
    max_tokens: int = 2400,
) -> int:
    """Calculate max output tokens for a transcript window."""
    if duration_seconds <= 0:
        raise ValueError("duration_seconds must be positive")
    calculated = int(duration_seconds * tokens_per_second)
    return min(max(calculated, min_tokens), max_tokens)


def normalize_anchor_text(value: str) -> str:
    """Normalize text for anchor matching."""
    lowered = value.lower().replace("-", " ")
    normalized = re.sub(r"[^a-z0-9]+", " ", lowered)
    return " ".join(normalized.split())


def score_anchor_region(
    *,
    region_name: str,
    transcript_text: str,
    anchors: tuple[str, ...],
) -> dict[str, Any]:
    """Score one named anchor region against transcript text."""
    normalized_text = normalize_anchor_text(transcript_text)
    found = {}
    for anchor in anchors:
        normalized_anchor = normalize_anchor_text(anchor)
        found[anchor] = bool(
            normalized_anchor
            and re.search(
                rf"(?<![a-z0-9]){re.escape(normalized_anchor)}(?![a-z0-9])",
                normalized_text,
            )
        )
    hits = sum(1 for value in found.values() if value)
    return {
        "region": region_name,
        "hits": hits,
        "total": len(anchors),
        "found": found,
    }


def detect_repetition(transcript_text: str) -> RepetitionResult:
    """Detect obvious repeated sentence blocks in generated transcript text."""
    normalized = " ".join(transcript_text.split())
    if not normalized:
        return RepetitionResult(has_warning=False)

    sentences = [
        normalize_anchor_text(item)
        for item in re.split(r"(?<=[.!?])\s+", normalized)
        if len(normalize_anchor_text(item).split()) >= 3
    ]
    sentence_counts = Counter(sentences)
    for sentence, count in sentence_counts.items():
        if count >= 4:
            return RepetitionResult(
                has_warning=True,
                repeated_text=sentence,
                repeat_count=count,
            )

    words = normalize_anchor_text(normalized).split()
    for block_size in range(3, min(8, len(words) // 2) + 1):
        blocks = [
            " ".join(words[index : index + block_size])
            for index in range(0, len(words) - block_size + 1, block_size)
        ]
        block_counts = Counter(blocks)
        repeated, count = block_counts.most_common(1)[0]
        if count >= 4:
            return RepetitionResult(
                has_warning=True,
                repeated_text=repeated,
                repeat_count=count,
            )

    if len(words) < 24:
        return RepetitionResult(has_warning=False)
    shingles = [" ".join(words[index : index + 8]) for index in range(len(words) - 7)]
    shingle_counts = Counter(shingles)
    repeated, count = shingle_counts.most_common(1)[0]
    if count >= 6:
        return RepetitionResult(
            has_warning=True,
            repeated_text=repeated,
            repeat_count=count,
        )
    return RepetitionResult(has_warning=False)


def _cost(tokens: int, per_million: float) -> float:
    return round((tokens / 1_000_000) * per_million, 6)


def calculate_cost(usage: TokenUsage, pricing: PricingProfile) -> CostBreakdown:
    """Calculate estimated Gemini API cost from token usage."""
    if usage.video_input_tokens is not None or usage.audio_input_tokens is not None:
        video_tokens = usage.video_input_tokens or 0
        audio_tokens = usage.audio_input_tokens or 0
        remaining_tokens = max(usage.input_tokens - video_tokens - audio_tokens, 0)
        input_cost = (
            _cost(
                video_tokens + remaining_tokens,
                pricing.text_image_video_input_per_million,
            )
            + _cost(audio_tokens, pricing.audio_input_per_million)
        )
        audio_available = True
    else:
        input_cost = _cost(
            usage.input_tokens,
            pricing.text_image_video_input_per_million,
        )
        audio_available = False

    output_cost = _cost(usage.output_tokens, pricing.output_per_million)
    return CostBreakdown(
        input_cost_usd=round(input_cost, 6),
        output_cost_usd=output_cost,
        total_cost_usd=round(input_cost + output_cost, 6),
        audio_costing_available=audio_available,
    )


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


def aggregate_run_summary(
    *,
    video: BenchmarkVideo,
    combination: BenchmarkCombination,
    model: str,
    prompt_variant: str,
    media_resolution: str,
    output_cap_tokens: int,
    concurrency: int,
    run_number: int,
    wall_clock_seconds: float,
    calls: list[CallResult],
    pricing: PricingProfile,
) -> dict[str, Any]:
    """Aggregate per-window call results into one run summary."""
    ordered_calls = sorted(calls, key=lambda item: item.window.start_seconds)
    stitched = "\n\n".join(
        call.transcript_text.strip()
        for call in ordered_calls
        if call.transcript_text.strip()
    )
    usage = TokenUsage(
        input_tokens=sum(call.token_usage.input_tokens for call in ordered_calls),
        output_tokens=sum(call.token_usage.output_tokens for call in ordered_calls),
        total_tokens=sum(call.token_usage.total_tokens for call in ordered_calls),
        cached_tokens=sum(call.token_usage.cached_tokens for call in ordered_calls),
        video_input_tokens=(
            sum(call.token_usage.video_input_tokens or 0 for call in ordered_calls)
            if any(call.token_usage.video_input_tokens is not None for call in ordered_calls)
            else None
        ),
        audio_input_tokens=(
            sum(call.token_usage.audio_input_tokens or 0 for call in ordered_calls)
            if any(call.token_usage.audio_input_tokens is not None for call in ordered_calls)
            else None
        ),
    )
    cost = calculate_cost(usage, pricing)
    anchor_results = [
        score_anchor_region(
            region_name=region.name,
            transcript_text="\n\n".join(
                call.transcript_text.strip()
                for call in ordered_calls
                if call.window.start_seconds < region.end_seconds
                and call.window.end_seconds > region.start_seconds
                and call.transcript_text.strip()
            ),
            anchors=region.anchors,
        )
        for region in video.anchor_regions
    ]
    anchor_hits = sum(int(result["hits"]) for result in anchor_results)
    anchor_total = sum(int(result["total"]) for result in anchor_results)
    repetition = detect_repetition(stitched)

    return {
        "video_id": video.video_id,
        "title": video.title,
        "duration_seconds": video.duration_seconds,
        "model": model,
        "prompt_variant": prompt_variant,
        "media_resolution": media_resolution,
        "combination": combination.label,
        "window_seconds": combination.window_seconds,
        "overlap_seconds": combination.overlap_seconds,
        "output_cap_tokens": output_cap_tokens,
        "concurrency": concurrency,
        "run_number": run_number,
        "call_count": len(ordered_calls),
        "failed_call_count": sum(1 for call in ordered_calls if call.error),
        "wall_clock_seconds": round(wall_clock_seconds, 3),
        "summed_call_latency_seconds": round(
            sum(call.elapsed_seconds for call in ordered_calls),
            3,
        ),
        "input_tokens": usage.input_tokens,
        "output_tokens": usage.output_tokens,
        "total_tokens": usage.total_tokens,
        "video_input_tokens": usage.video_input_tokens,
        "audio_input_tokens": usage.audio_input_tokens,
        "input_cost_usd": cost.input_cost_usd,
        "output_cost_usd": cost.output_cost_usd,
        "estimated_cost_usd": cost.total_cost_usd,
        "audio_costing_available": cost.audio_costing_available,
        "anchor_score": f"{anchor_hits}/{anchor_total}",
        "anchor_results": anchor_results,
        "repetition_warning": repetition.has_warning,
        "word_count": len(stitched.split()),
        "stitched_transcript": stitched,
    }


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


def _summary_column_label(column: str) -> str:
    """Return markdown table label for a summary column."""
    return column.replace("_", " ").title().replace(" Id", " ID")


def _format_markdown_cell(value: Any) -> str:
    """Return a value safe for one markdown table cell."""
    normalized = " ".join(str(value).split())
    return normalized.replace("\\", "\\\\").replace("|", "\\|")


def write_reports(*, output_dir: Path, summaries: list[dict[str, Any]]) -> None:
    """Write JSON, markdown, and CSV benchmark summaries."""
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "summary.json").write_text(
        json.dumps(summaries, indent=2),
        encoding="utf-8",
    )

    with (output_dir / "summary.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=SUMMARY_COLUMNS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(summaries)

    header = (
        "| "
        + " | ".join(_summary_column_label(column) for column in SUMMARY_COLUMNS)
        + " |"
    )
    separator = "| " + " | ".join("---" for _ in SUMMARY_COLUMNS) + " |"
    rows = [
        "| "
        + " | ".join(_format_markdown_cell(summary.get(column, "")) for column in SUMMARY_COLUMNS)
        + " |"
        for summary in summaries
    ]
    (output_dir / "summary.md").write_text(
        "\n".join([header, separator, *rows]) + "\n",
        encoding="utf-8",
    )
