"""Service helpers for appending YouTube transcripts to website content."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import uuid
from typing import Optional

from sqlalchemy.orm import Session

from api.executors.skill_executor import SkillExecutor
from api.services.websites_service import WebsitesService


_YOUTUBE_ID_PATTERN = re.compile(
    r"(?:youtube\.com/(?:watch\?v=|embed/)|youtu\.be/)([A-Za-z0-9_-]+)"
)


@dataclass(frozen=True)
class TranscriptAppendResult:
    """Result for transcript append operations."""

    content: str
    changed: bool


def extract_youtube_id(url: str) -> Optional[str]:
    """Extract a YouTube video ID from a URL."""
    if not url:
        return None
    match = _YOUTUBE_ID_PATTERN.search(url)
    return match.group(1) if match else None


def split_frontmatter(markdown: str) -> tuple[str, str]:
    """Split markdown into frontmatter and body."""
    trimmed = markdown.lstrip()
    if not trimmed.startswith("---"):
        return "", markdown
    lines = markdown.splitlines()
    if not lines or lines[0].strip() != "---":
        return "", markdown
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            frontmatter = "\n".join(lines[: idx + 1]).rstrip() + "\n\n"
            body = "\n".join(lines[idx + 1 :]).lstrip("\n")
            return frontmatter, body
    return "", markdown


def append_transcript_to_markdown(
    markdown: str,
    *,
    youtube_url: str,
    transcript_text: str,
) -> TranscriptAppendResult:
    """Append transcript text below the YouTube embed link."""
    video_id = extract_youtube_id(youtube_url)
    if not video_id:
        return TranscriptAppendResult(content=markdown, changed=False)

    marker = f"<!-- YOUTUBE_TRANSCRIPT:{video_id} -->"
    if marker in markdown:
        return TranscriptAppendResult(content=markdown, changed=False)

    frontmatter, body = split_frontmatter(markdown)
    body_lines = body.splitlines()
    insert_at = len(body_lines)
    video_pattern = re.compile(rf"(youtube\.com|youtu\.be).+{re.escape(video_id)}")
    for idx, line in enumerate(body_lines):
        if video_pattern.search(line):
            insert_at = idx + 1
            break

    transcript_body = split_frontmatter(transcript_text)[1].strip()
    if transcript_body:
        normalized = transcript_body.replace("\r\n", "\n").strip()
        transcript_lines = normalized.splitlines()
        separator_index = next(
            (idx for idx, line in enumerate(transcript_lines) if line.strip() == "---"),
            None,
        )
        if separator_index is not None:
            header_lines = [
                line for line in transcript_lines[:separator_index] if line.strip()
            ]
            if header_lines and all(line.lstrip().startswith("#") for line in header_lines):
                transcript_body = "\n".join(
                    transcript_lines[separator_index + 1 :]
                ).strip()
    if not transcript_body:
        return TranscriptAppendResult(content=markdown, changed=False)

    transcript_block = [
        "",
        marker,
        "",
        "### Transcript",
        "",
        transcript_body,
        "",
    ]
    body_lines[insert_at:insert_at] = transcript_block
    updated_body = "\n".join(body_lines).rstrip()
    return TranscriptAppendResult(
        content=f"{frontmatter}{updated_body}\n",
        changed=True,
    )


class WebsiteTranscriptService:
    """Transcribe YouTube videos and append transcripts to websites."""

    @staticmethod
    async def append_youtube_transcript(
        db: Session,
        executor: SkillExecutor,
        user_id: str,
        website_id: uuid.UUID,
        youtube_url: str,
    ) -> str:
        """Append a YouTube transcript to a website's markdown content."""
        website = WebsitesService.get_website(db, user_id, website_id, mark_opened=False)
        if not website:
            raise ValueError("Website not found")

        content = website.content or ""
        video_id = extract_youtube_id(youtube_url)
        if not video_id:
            raise ValueError("Invalid YouTube URL")

        marker = f"<!-- YOUTUBE_TRANSCRIPT:{video_id} -->"
        if marker in content:
            return content

        result = await executor.execute(
            "youtube-transcribe",
            "transcribe_youtube.py",
            [youtube_url, "--user-id", user_id],
        )
        if not result.get("success"):
            raise RuntimeError(result.get("error", "Failed to transcribe YouTube"))

        data = result.get("data") or {}
        transcript_path = data.get("transcript_local_path") or data.get("transcript_file")
        if not transcript_path:
            raise RuntimeError("Transcript path missing from transcriber output")

        transcript_text = Path(transcript_path).read_text(encoding="utf-8")
        append_result = append_transcript_to_markdown(
            content,
            youtube_url=youtube_url,
            transcript_text=transcript_text,
        )
        if not append_result.changed:
            return content

        WebsitesService.update_website(
            db,
            user_id,
            website_id,
            content=append_result.content,
        )
        return append_result.content
