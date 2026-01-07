"""Helper functions for ingestion routes."""
from __future__ import annotations

from hashlib import sha256
import logging
from pathlib import Path
import shutil
import urllib.parse
import uuid

from fastapi import UploadFile
from sqlalchemy.orm import Session

from api.config import settings
from api.exceptions import APIError, BadRequestError, InternalServerError, PayloadTooLargeError
from api.models.file_ingestion import IngestedFile
from api.services.file_ingestion_service import FileIngestionService
from api.services.storage.service import get_storage_backend

logger = logging.getLogger(__name__)

MAX_FILE_BYTES = 100 * 1024 * 1024
STAGING_ROOT = Path("/tmp/sidebar-ingestion")
ERROR_MESSAGES = {
    "FILE_NOT_FOUND": "We couldn't find the uploaded file. Please try again.",
    "SOURCE_MISSING": "The upload could not be found. Please upload it again.",
    "FILE_EMPTY": "This file appears to be empty.",
    "UNSUPPORTED_TYPE": "That file type isn't supported yet.",
    "CONVERSION_UNAVAILABLE": "File conversion is unavailable right now.",
    "CONVERSION_TIMEOUT": "File conversion timed out. We'll retry automatically.",
    "CONVERSION_FAILED": "We couldn't convert this file.",
    "DERIVATIVE_MISSING": "We couldn't generate a preview for this file.",
    "INVALID_XLSX": "That doesn't appear to be a valid XLSX file. Try re-saving it as .xlsx in Excel or Google Sheets.",
    "TRANSCRIPTION_UNAVAILABLE": "Audio transcription is unavailable right now.",
    "TRANSCRIPTION_FAILED": "We couldn't transcribe this audio file.",
    "VIDEO_TRANSCRIPTION_FAILED": "We couldn't transcribe this video.",
    "VIDEO_TRANSCRIPTION_UNAVAILABLE": "Video transcription is unavailable right now.",
    "INVALID_YOUTUBE_URL": "That doesn't look like a valid YouTube URL.",
    "WORKER_STALLED": "Processing took too long. We're retrying.",
    "UNKNOWN_ERROR": "Something went wrong while processing this file.",
}


def _staging_path(file_id: uuid.UUID) -> Path:
    return STAGING_ROOT / str(file_id) / "source"


def _safe_cleanup(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path.parent, ignore_errors=True)


def _staging_storage_key(user_id: str, file_id: uuid.UUID) -> str:
    return f"{user_id}/files/{file_id}/staging/source"


async def _handle_upload(
    file: UploadFile,
    folder: str,
    user_id: str,
    db: Session,
) -> tuple[uuid.UUID, uuid.UUID]:
    file_id = uuid.uuid4()
    staging_path = _staging_path(file_id)
    staging_path.parent.mkdir(parents=True, exist_ok=True)

    digest = sha256()
    size = 0

    storage = None
    staged_key: str | None = None
    try:
        with staging_path.open("wb") as target:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_FILE_BYTES:
                    raise PayloadTooLargeError("File too large")
                digest.update(chunk)
                target.write(chunk)

        mime_original = file.content_type or "application/octet-stream"
        mime_original = mime_original.split(";")[0].strip().lower()
        if not mime_original:
            mime_original = "application/octet-stream"
        filename = file.filename or "upload"
        path = _build_ingestion_path(folder, filename)
        _, job = FileIngestionService.create_ingestion(
            db,
            user_id,
            filename_original=filename,
            path=path,
            mime_original=mime_original,
            size_bytes=size,
            sha256=digest.hexdigest(),
            file_id=file_id,
        )
        if settings.storage_backend.lower() == "r2":
            storage = get_storage_backend()
            staged_key = _staging_storage_key(user_id, file_id)
            storage.put_object(staged_key, staging_path.read_bytes(), content_type=mime_original)
    except APIError:
        _safe_cleanup(staging_path)
        if staged_key and storage:
            storage.delete_object(staged_key)
        raise
    except Exception as exc:
        logger.exception("Ingestion upload failed")
        _safe_cleanup(staging_path)
        if staged_key and storage:
            storage.delete_object(staged_key)
        raise InternalServerError("Upload failed") from exc

    return file_id, job.id


def _build_ingestion_path(folder: str | None, filename: str) -> str:
    clean_folder = (folder or "").strip().strip("/")
    if clean_folder:
        return f"{clean_folder}/{filename}"
    return filename


def _filter_user_derivatives(derivatives: list[dict], user_id: str) -> list[dict]:
    prefix = f"{user_id}/"
    return [item for item in derivatives if item.get("storage_key", "").startswith(prefix)]


def _recommended_viewer(derivatives: list[dict], record: IngestedFile | None = None) -> str | None:
    kinds = {item["kind"] for item in derivatives}
    if "viewer_pdf" in kinds:
        return "viewer_pdf"
    if "viewer_json" in kinds:
        return "viewer_json"
    if record and record.source_url and record.mime_original.startswith("video/"):
        return "viewer_video"
    if "image_original" in kinds:
        return "image_original"
    if "audio_original" in kinds:
        return "audio_original"
    if "text_original" in kinds:
        return "text_original"
    if "ai_md" in kinds:
        return "ai_md"
    return None


def _normalize_youtube_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url if url.startswith(("http://", "https://")) else f"https://{url}")
    if not parsed.netloc:
        raise BadRequestError("Invalid URL")
    if not any(domain in parsed.netloc for domain in ("youtube.com", "youtu.be")):
        raise BadRequestError("Invalid YouTube URL")
    if "youtu.be" in parsed.netloc:
        video_id = parsed.path.strip("/")
        if not video_id:
            raise BadRequestError("Invalid YouTube URL")
        return f"https://www.youtube.com/watch?v={video_id}"
    if parsed.path.startswith("/shorts/"):
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) >= 2:
            return f"https://www.youtube.com/watch?v={parts[1]}"
    return url


def _extract_youtube_id(url: str) -> str | None:
    try:
        parsed = urllib.parse.urlparse(url)
        if "youtu.be" in parsed.netloc:
            return parsed.path.strip("/") or None
        query = urllib.parse.parse_qs(parsed.query)
        if "v" in query and query["v"]:
            return query["v"][0]
        if parsed.path.startswith("/shorts/"):
            parts = [part for part in parsed.path.split("/") if part]
            if len(parts) >= 2:
                return parts[1]
    except Exception:
        return None
    return None


def _category_for_file(
    filename: str,
    mime: str,
    *,
    path: str | None = None,
    source_metadata: dict | None = None,
) -> str:
    lower_name = filename.lower()
    normalized_mime = (mime or "application/octet-stream").split(";")[0].strip().lower()
    if source_metadata and source_metadata.get("provider") == "web-crawler-policy":
        return "reports"
    if path:
        normalized_path = path.strip("/")
        if normalized_path.lower().startswith("reports/"):
            return "reports"
    if lower_name.endswith((".csv", ".tsv")):
        return "spreadsheets"
    if normalized_mime == "application/octet-stream":
        if lower_name.endswith((".csv", ".tsv", ".xls", ".xlsx", ".xlsm", ".xltx", ".xltm")):
            return "spreadsheets"
        if lower_name.endswith((".md", ".markdown", ".txt", ".log", ".json", ".yml", ".yaml", ".pdf")):
            return "documents"
    if normalized_mime.startswith("image/"):
        return "images"
    if normalized_mime == "application/pdf":
        return "documents"
    if normalized_mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
        return "documents"
    if normalized_mime in {
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-excel",
        "text/csv",
        "application/csv",
        "text/tab-separated-values",
        "text/tsv",
    }:
        return "spreadsheets"
    if normalized_mime == "application/vnd.openxmlformats-officedocument.presentationml.presentation":
        return "presentations"
    if normalized_mime.startswith("text/"):
        return "documents"
    if normalized_mime.startswith("audio/"):
        return "audio"
    if normalized_mime.startswith("video/"):
        return "video"
    return "other"


def _user_message_for_error(error_code: str | None, status: str | None) -> str | None:
    if not error_code or status != "failed":
        return None
    return ERROR_MESSAGES.get(error_code, "We couldn't process this file. Please try again.")
