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
import sys
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
    return len(re.findall(r"\b\w+\b", text))


def heading_count(text: str) -> int:
    return len(re.findall(r"^#{1,6}\s+", text, flags=re.MULTILINE))


def image_count(text: str) -> int:
    return len(re.findall(r"!\[[^\]]*\]\([^)]+\)", text))


def link_count(text: str) -> int:
    return len(re.findall(r"\[[^\]]+\]\([^)]+\)", text))


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
                writer.writerow([entry_id, url, status, error] + [""] * 12)
                continue

            try:
                parsed = parse_url_local(url)
                local_md = strip_frontmatter(parsed.content)
            except Exception as exc:
                status = "error"
                error = f"parse_error: {exc}"
                writer.writerow([entry_id, url, status, error] + [""] * 12)
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
                    f"{similarity(goodlinks_body, local_body):.3f}",
                    diff_path,
                ]
            )

    print(f"Wrote {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
