#!/usr/bin/env python3
"""
Compare GoodLinks markdown exports against local parser output.

Usage:
  python goodlinks-testing/compare_goodlinks.py --limit 10
"""
from __future__ import annotations

import argparse
import csv
import difflib
import re
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Optional

REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = REPO_ROOT / "backend"
sys.path.insert(0, str(BACKEND_ROOT))

from api.services.web_save_parser import parse_url_local  # noqa: E402


def strip_frontmatter(text: str) -> str:
    trimmed = text.strip()
    if not trimmed.startswith("---"):
        return text
    match = re.match(r"^---\s*\n[\s\S]*?\n---\s*\n?", trimmed)
    if match:
        return trimmed[match.end():]
    lines = trimmed.splitlines()
    try:
        idx = lines.index("---")
    except ValueError:
        return text
    return "\n".join(lines[idx + 1 :])


def word_count(text: str) -> int:
    scrubbed = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", text)
    scrubbed = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", scrubbed)
    scrubbed = re.sub(r"https?://\S+", "", scrubbed)
    return len(re.findall(r"\b\w+\b", scrubbed))


def heading_count(text: str) -> int:
    return len(re.findall(r"^#{1,6}\s+", text, flags=re.MULTILINE))


def image_count(text: str) -> int:
    return len(re.findall(r"!\[[^\]]*\]\([^)]+\)", text))


def link_count(text: str) -> int:
    return len(re.findall(r"\[[^\]]+\]\([^)]+\)", text))


def video_count(text: str) -> int:
    video_hosts = ("youtube.com", "youtu.be", "vimeo.com", "player.vimeo.com")
    matches = re.findall(r"\[[^\]]+\]\(([^)]+)\)", text)
    return sum(1 for url in matches if any(host in url for host in video_hosts))


def similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a, b).ratio()


def first_diff_snippet(a: str, b: str, *, max_lines: int = 6) -> str:
    a_lines = a.splitlines()
    b_lines = b.splitlines()
    diff = list(difflib.ndiff(a_lines, b_lines))
    snippet = []
    for line in diff:
        if line.startswith(("-", "+", "?")):
            snippet.append(line)
        if len(snippet) >= max_lines:
            break
    return "\\n".join(snippet)


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare GoodLinks markdown with local parser.")
    parser.add_argument(
        "--csv",
        default=str(REPO_ROOT / "goodlinks-testing" / "goodlinks_test_urls.csv"),
        help="CSV with id,url columns.",
    )
    parser.add_argument(
        "--articles-dir",
        default=str(REPO_ROOT / "goodlinks-testing" / "gl-articles"),
        help="Directory containing GoodLinks markdown files.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(REPO_ROOT / "goodlinks-testing" / "comparison"),
        help="Directory to write summary and diffs.",
    )
    parser.add_argument("--limit", type=int, default=None, help="Limit number of rows to compare.")
    parser.add_argument(
        "--ids",
        nargs="*",
        default=None,
        help="Specific IDs to compare (e.g. gl-001 gl-010).",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)
    csv_path = Path(args.csv)
    articles_dir = Path(args.articles_dir)
    output_dir = Path(args.output_dir)
    diffs_dir = output_dir / "diffs"
    output_dir.mkdir(parents=True, exist_ok=True)
    diffs_dir.mkdir(parents=True, exist_ok=True)

    with csv_path.open() as f:
        rows = list(csv.DictReader(f))

    if args.ids:
        wanted = {value.strip() for value in args.ids}
        rows = [row for row in rows if row.get("id") in wanted]

    if args.limit:
        rows = rows[: args.limit]

    summary_path = output_dir / "summary.csv"
    history_path = output_dir / "history.csv"
    ok_rows = []
    error_count = 0
    with summary_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "id",
                "url",
                "status",
                "error",
                "goodlinks_chars",
                "local_chars",
                "goodlinks_words",
                "local_words",
                "goodlinks_headings",
                "local_headings",
                "goodlinks_images",
                "local_images",
                "goodlinks_links",
                "local_links",
                "goodlinks_videos",
                "local_videos",
                "similarity",
                "diff_path",
            ]
        )

        for row in rows:
            entry_id = row.get("id") or ""
            url = row.get("url") or ""
            article_path = articles_dir / f"{entry_id}.txt"
            status = "ok"
            error = ""
            diff_path = ""

            try:
                goodlinks_md = article_path.read_text(errors="ignore")
            except Exception as exc:
                status = "error"
                error = f"read_error: {exc}"
                writer.writerow([entry_id, url, status, error] + [""] * 14)
                error_count += 1
                continue

            try:
                parsed = parse_url_local(url)
                local_md = strip_frontmatter(parsed.content)
            except Exception as exc:
                status = "error"
                error = f"parse_error: {exc}"
                writer.writerow([entry_id, url, status, error] + [""] * 14)
                error_count += 1
                continue

            goodlinks_body = goodlinks_md.strip()
            local_body = local_md.strip()

            diff_text = first_diff_snippet(goodlinks_body, local_body)
            if diff_text:
                diff_path = str(diffs_dir / f"{entry_id}.diff")
                (diffs_dir / f"{entry_id}.diff").write_text(diff_text)

            writer.writerow(
                [
                    entry_id,
                    url,
                    status,
                    error,
                    len(goodlinks_body),
                    len(local_body),
                    word_count(goodlinks_body),
                    word_count(local_body),
                    heading_count(goodlinks_body),
                    heading_count(local_body),
                    image_count(goodlinks_body),
                    image_count(local_body),
                    link_count(goodlinks_body),
                    link_count(local_body),
                    video_count(goodlinks_body),
                    video_count(local_body),
                    f"{similarity(goodlinks_body, local_body):.3f}",
                    diff_path,
                ]
            )
            ok_rows.append(
                {
                    "goodlinks_words": word_count(goodlinks_body),
                    "local_words": word_count(local_body),
                    "goodlinks_links": link_count(goodlinks_body),
                    "local_links": link_count(local_body),
                    "goodlinks_images": image_count(goodlinks_body),
                    "local_images": image_count(local_body),
                    "goodlinks_videos": video_count(goodlinks_body),
                    "local_videos": video_count(local_body),
                    "similarity": similarity(goodlinks_body, local_body),
                }
            )

    if ok_rows:
        def compute_diff(rows: list[dict], key: str) -> tuple[int, int]:
            missing = 0
            extra = 0
            for item in rows:
                gl = int(item[f"goodlinks_{key}"])
                local = int(item[f"local_{key}"])
                if local < gl:
                    missing += gl - local
                elif local > gl:
                    extra += local - gl
            return missing, extra

        similarities = [item["similarity"] for item in ok_rows]
        avg_similarity = sum(similarities) / len(similarities)
        std_similarity = (
            statistics.pstdev(similarities) if len(similarities) > 1 else 0.0
        )
        missing_words, extra_words = compute_diff(ok_rows, "words")
        missing_links, extra_links = compute_diff(ok_rows, "links")
        missing_images, extra_images = compute_diff(ok_rows, "images")
        missing_videos, extra_videos = compute_diff(ok_rows, "videos")
        def coverage_ratios(rows: list[dict], key: str) -> list[float]:
            ratios: list[float] = []
            for item in rows:
                goodlinks_value = int(item[f"goodlinks_{key}"])
                local_value = int(item[f"local_{key}"])
                if goodlinks_value == 0:
                    ratios.append(1.0)
                else:
                    ratios.append(min(goodlinks_value, local_value) / goodlinks_value)
            return ratios

        def aggregate_coverage(ratios: list[float]) -> float:
            if not ratios:
                return 1.0
            return sum(ratios) / len(ratios)

        def coverage_std(ratios: list[float]) -> float:
            return statistics.pstdev(ratios) if len(ratios) > 1 else 0.0

        ratios_words = coverage_ratios(ok_rows, "words")
        ratios_links = coverage_ratios(ok_rows, "links")
        ratios_images = coverage_ratios(ok_rows, "images")
        ratios_videos = coverage_ratios(ok_rows, "videos")
        coverage_words = aggregate_coverage(ratios_words)
        coverage_links = aggregate_coverage(ratios_links)
        coverage_images = aggregate_coverage(ratios_images)
        coverage_videos = aggregate_coverage(ratios_videos)
        std_coverage_words = coverage_std(ratios_words)
        std_coverage_links = coverage_std(ratios_links)
        std_coverage_images = coverage_std(ratios_images)
        std_coverage_videos = coverage_std(ratios_videos)

        try:
            git_sha = (
                subprocess.check_output(
                    ["git", "rev-parse", "--short", "HEAD"],
                    cwd=REPO_ROOT,
                    text=True,
                )
                .strip()
            )
        except Exception:
            git_sha = "unknown"

        run_at = datetime.now(timezone.utc).isoformat()
        history_fields = [
            "run_at",
            "git_sha",
            "ok_count",
            "error_count",
            "avg_similarity",
            "std_similarity",
            "coverage_words",
            "std_coverage_words",
            "coverage_links",
            "std_coverage_links",
            "coverage_images",
            "std_coverage_images",
            "coverage_videos",
            "std_coverage_videos",
            "missing_words",
            "extra_words",
            "missing_links",
            "extra_links",
            "missing_images",
            "extra_images",
            "missing_videos",
            "extra_videos",
        ]
        existing_rows: list[dict[str, str]] = []
        rewrite_history = False
        if history_path.exists():
            with history_path.open() as f:
                reader = csv.DictReader(f)
                existing_fields = reader.fieldnames or []
                if existing_fields != history_fields:
                    rewrite_history = True
                    existing_rows = list(reader)
        mode = "w" if rewrite_history or not history_path.exists() else "a"
        with history_path.open(mode, newline="") as f:
            writer = csv.writer(f)
            if mode == "w":
                writer.writerow(history_fields)
                for row in existing_rows:
                    writer.writerow([row.get(field, "") for field in history_fields])
            writer.writerow(
                [
                    run_at,
                    git_sha,
                    len(ok_rows),
                    error_count,
                    f"{avg_similarity:.4f}",
                    f"{std_similarity:.4f}",
                    f"{coverage_words:.4f}",
                    f"{std_coverage_words:.4f}",
                    f"{coverage_links:.4f}",
                    f"{std_coverage_links:.4f}",
                    f"{coverage_images:.4f}",
                    f"{std_coverage_images:.4f}",
                    f"{coverage_videos:.4f}",
                    f"{std_coverage_videos:.4f}",
                    missing_words,
                    extra_words,
                    missing_links,
                    extra_links,
                    missing_images,
                    extra_images,
                    missing_videos,
                    extra_videos,
                ]
            )

    print(f"Wrote {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
