"""Service helpers for appending YouTube transcripts to website content."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.services.file_ingestion_service import FileIngestionService
from api.services.url_normalization_service import (
    extract_youtube_video_id,
)
from api.services.url_normalization_service import (
    normalize_youtube_url as normalize_youtube_url_shared,
)
from api.services.websites_service import WebsitesService


@dataclass(frozen=True)
class TranscriptAppendResult:
    """Result for transcript append operations."""

    content: str
    changed: bool


@dataclass(frozen=True)
class TranscriptEnqueueResult:
    """Result for enqueuing transcript jobs."""

    status: str
    content: str | None
    file_id: uuid.UUID | None


def extract_youtube_id(url: str) -> str | None:
    """Extract a YouTube video ID from a URL."""
    return extract_youtube_video_id(url)


def normalize_youtube_url(url: str) -> str:
    """Normalize a YouTube URL to a canonical watch link."""
    return normalize_youtube_url_shared(url)


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
    video_title: str | None = None,
) -> TranscriptAppendResult:
    """Append transcript text to the end of the markdown."""
    video_id = extract_youtube_id(youtube_url)
    if not video_id:
        return TranscriptAppendResult(content=markdown, changed=False)

    marker = f"<!-- YOUTUBE_TRANSCRIPT:{video_id} -->"
    if marker in markdown:
        return TranscriptAppendResult(content=markdown, changed=False)

    frontmatter, body = split_frontmatter(markdown)
    body_lines = body.splitlines()

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
            if header_lines and all(
                line.lstrip().startswith("#") for line in header_lines
            ):
                transcript_body = "\n".join(
                    transcript_lines[separator_index + 1 :]
                ).strip()
    if not transcript_body:
        return TranscriptAppendResult(content=markdown, changed=False)

    title = (video_title or "").strip() or "YouTube"
    transcript_block = [
        "___",
        "",
        marker,
        "",
        f"### Transcript of {title} video",
        "",
        transcript_body,
    ]
    block_text = "\n".join(transcript_block).rstrip()
    existing_body = "\n".join(body_lines).rstrip()
    updated_body = f"{existing_body}\n\n{block_text}" if existing_body else block_text
    return TranscriptAppendResult(
        content=f"{frontmatter}{updated_body}\n",
        changed=True,
    )


class WebsiteTranscriptService:
    """Transcribe YouTube videos and append transcripts to websites."""

    @staticmethod
    def enqueue_youtube_transcript(
        db: Session,
        user_id: str,
        website_id: uuid.UUID,
        youtube_url: str,
    ) -> TranscriptEnqueueResult:
        """Queue a YouTube transcript job and return its status."""
        website = WebsitesService.get_website(
            db, user_id, website_id, mark_opened=False
        )
        if not website:
            raise ValueError("Website not found")

        normalized_url = normalize_youtube_url(youtube_url)
        content = website.content or ""
        video_id = extract_youtube_id(normalized_url)
        if not video_id:
            raise ValueError("Invalid YouTube URL")

        marker = f"<!-- YOUTUBE_TRANSCRIPT:{video_id} -->"
        if marker in content:
            return TranscriptEnqueueResult(
                status="ready", content=content, file_id=None
            )

        record, _job = FileIngestionService.create_ingestion(
            db,
            user_id,
            filename_original="YouTube transcript",
            mime_original="video/youtube",
            size_bytes=0,
            sha256=None,
            source_url=normalized_url,
            source_metadata={
                "provider": "youtube",
                "video_id": video_id,
                "youtube_url": normalized_url,
                "website_id": str(website_id),
                "website_transcript": True,
            },
        )

        WebsiteTranscriptService._update_transcript_metadata(
            db,
            website,
            video_id,
            status="queued",
            file_id=str(record.id),
        )

        return TranscriptEnqueueResult(
            status="queued",
            content=None,
            file_id=record.id,
        )

    @staticmethod
    def append_transcript_from_text(
        db: Session,
        *,
        user_id: str,
        website_id: uuid.UUID,
        youtube_url: str,
        transcript_text: str,
        video_title: str | None = None,
    ) -> str:
        """Append transcript text to a website and return updated content."""
        website = WebsitesService.get_website(
            db, user_id, website_id, mark_opened=False
        )
        if not website:
            raise ValueError("Website not found")

        normalized_url = normalize_youtube_url(youtube_url)
        video_id = extract_youtube_id(normalized_url)
        if not video_id:
            raise ValueError("Invalid YouTube URL")

        append_result = append_transcript_to_markdown(
            website.content or "",
            youtube_url=normalized_url,
            transcript_text=transcript_text,
            video_title=video_title,
        )
        if not append_result.changed:
            return website.content or ""

        WebsitesService.update_website(
            db,
            user_id,
            website_id,
            content=append_result.content,
        )
        WebsiteTranscriptService._update_transcript_metadata(
            db,
            website,
            video_id,
            status="ready",
        )
        return append_result.content

    @staticmethod
    def update_transcript_status(
        db: Session,
        *,
        user_id: str,
        website_id: uuid.UUID,
        youtube_url: str,
        status: str,
        file_id: str | None = None,
        error: str | None = None,
    ) -> None:
        """Update transcript job metadata on a website."""
        website = WebsitesService.get_website(
            db, user_id, website_id, mark_opened=False
        )
        if not website:
            return
        try:
            normalized_url = normalize_youtube_url(youtube_url)
        except ValueError:
            return
        video_id = extract_youtube_id(normalized_url)
        if not video_id:
            return
        WebsiteTranscriptService._update_transcript_metadata(
            db,
            website,
            video_id,
            status=status,
            file_id=file_id,
            error=error,
        )

    @staticmethod
    def sync_transcript_status_from_ingestion(
        db: Session,
        *,
        user_id: str,
        website_id: uuid.UUID,
        youtube_url: str,
        status: str,
        file_id: str | None = None,
        error: str | None = None,
    ) -> bool:
        """Sync transcript status from ingestion jobs when metadata is stale."""
        website = WebsitesService.get_website(
            db, user_id, website_id, mark_opened=False
        )
        if not website:
            return False
        try:
            normalized_url = normalize_youtube_url(youtube_url)
        except ValueError:
            return False
        video_id = extract_youtube_id(normalized_url)
        if not video_id:
            return False

        metadata = website.metadata_ or {}
        transcripts = metadata.get("youtube_transcripts")
        if not isinstance(transcripts, dict):
            transcripts = {}
        entry = transcripts.get(video_id) or {}
        current_status = entry.get("status")
        current_file_id = entry.get("file_id")
        current_error = entry.get("error")

        if (
            current_status == status
            and (not file_id or current_file_id == file_id)
            and (not error or current_error == error)
        ):
            return False

        WebsiteTranscriptService._update_transcript_metadata(
            db,
            website,
            video_id,
            status=status,
            file_id=file_id,
            error=error,
        )
        return True

    @staticmethod
    def sync_transcripts_for_website(
        db: Session,
        *,
        user_id: str,
        website_id: uuid.UUID,
    ) -> bool:
        """Sync transcript statuses for a website from ingestion jobs."""
        website = WebsitesService.get_website(
            db, user_id, website_id, mark_opened=False
        )
        if not website:
            return False
        metadata = website.metadata_ or {}
        transcripts = metadata.get("youtube_transcripts")
        if not isinstance(transcripts, dict) or not transcripts:
            return False

        updated = False
        status_map = {
            "queued": "queued",
            "processing": "processing",
            "ready": "ready",
            "failed": "failed",
            "canceled": "canceled",
            "paused": "canceled",
        }
        for video_id, entry in transcripts.items():
            if not isinstance(entry, dict):
                continue
            file_id = entry.get("file_id")
            if not file_id:
                continue
            try:
                file_uuid = uuid.UUID(str(file_id))
            except (ValueError, TypeError):
                continue
            job = FileIngestionService.get_job(db, file_uuid)
            if not job:
                continue
            mapped_status = status_map.get(job.status)
            if not mapped_status:
                continue
            error = job.error_message
            current_status = entry.get("status")
            current_error = entry.get("error")
            if mapped_status == current_status and (
                not error or error == current_error
            ):
                continue
            WebsiteTranscriptService._update_transcript_metadata(
                db,
                website,
                video_id,
                status=mapped_status,
                file_id=str(file_uuid),
                error=error,
            )
            updated = True
        return updated

    @staticmethod
    def _update_transcript_metadata(
        db: Session,
        website,
        video_id: str,
        *,
        status: str,
        file_id: str | None = None,
        error: str | None = None,
    ) -> None:
        metadata = website.metadata_ or {}
        transcripts = metadata.get("youtube_transcripts")
        if not isinstance(transcripts, dict):
            transcripts = {}
        entry = dict(transcripts.get(video_id, {}))
        entry["status"] = status
        entry["updated_at"] = datetime.now(UTC).isoformat()
        if file_id:
            entry["file_id"] = file_id
        if error:
            entry["error"] = error
        elif status in {"queued", "processing", "retrying", "ready"}:
            entry.pop("error", None)
        transcripts[video_id] = entry
        metadata["youtube_transcripts"] = transcripts
        website.metadata_ = metadata
        flag_modified(website, "metadata_")
        website.updated_at = datetime.now(UTC)
        db.commit()
