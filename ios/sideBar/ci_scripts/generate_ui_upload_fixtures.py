#!/usr/bin/env python3
"""Generate local-only upload fixtures for iOS UI testing."""

from __future__ import annotations

import base64
import hashlib
import sys
from pathlib import Path


def write_text(path: Path, content: str) -> None:
    """Write UTF-8 text content to a file."""
    path.write_text(content, encoding="utf-8")


def write_bytes(path: Path, content: bytes) -> None:
    """Write binary content to a file."""
    path.write_bytes(content)


def deterministic_bytes(size: int, seed: str) -> bytes:
    """Generate deterministic pseudo-random bytes for fixture payloads."""
    chunks: list[bytes] = []
    counter = 0
    while sum(len(chunk) for chunk in chunks) < size:
        digest = hashlib.sha256(f"{seed}:{counter}".encode()).digest()
        chunks.append(digest)
        counter += 1
    return b"".join(chunks)[:size]


def main() -> int:
    """Create deterministic local upload fixtures under the UI test fixture folder."""
    repo_root = Path(__file__).resolve().parents[3]
    fixtures_dir = (
        repo_root
        / "ios"
        / "sideBar"
        / "sideBarUITests"
        / "LocalUploadFixtures"
    )
    fixtures_dir.mkdir(parents=True, exist_ok=True)

    write_text(
        fixtures_dir / "sample-note.md",
        "# Upload Fixture Note\n\n- Deterministic\n- Safe for UI testing\n",
    )
    write_text(
        fixtures_dir / "sample-text.txt",
        "This is a deterministic text upload fixture for sideBar UI tests.\n",
    )
    write_text(
        fixtures_dir / "sample-data.csv",
        "id,title,status\n1,Upload fixture row,ready\n2,Second row,pending\n",
    )
    write_text(
        fixtures_dir / "sample-data.json",
        '{\n  "fixture": true,\n  "source": "ui-upload",\n'
        '  "items": [{"id": 1, "title": "Fixture item"}]\n}\n',
    )
    write_text(
        fixtures_dir / "sample-page.html",
        "<!doctype html><html><body><h1>Upload Fixture</h1></body></html>\n",
    )

    png_1x1_base64 = (
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8"
        "/x8AAusB9Y6s7WkAAAAASUVORK5CYII="
    )
    write_bytes(fixtures_dir / "sample-image.png", base64.b64decode(png_1x1_base64))
    write_bytes(
        fixtures_dir / "sample-binary-1mb.bin",
        deterministic_bytes(1_048_576, seed="sidebar-ui-upload-fixture"),
    )

    sys.stdout.write(f"Generated upload fixtures in {fixtures_dir}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
