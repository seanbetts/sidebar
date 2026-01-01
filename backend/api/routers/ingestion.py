"""File ingestion router for uploads and processing status."""
from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
import logging
from pathlib import Path
import shutil
import urllib.parse
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.file_ingestion_service import FileIngestionService
from api.services.storage.service import get_storage_backend
from api.models.file_ingestion import IngestedFile


router = APIRouter(prefix="/ingestion", tags=["ingestion"])
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
    return None


def _normalize_youtube_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url if url.startswith(("http://", "https://")) else f"https://{url}")
    if not parsed.netloc:
        raise HTTPException(status_code=400, detail="Invalid URL")
    if not any(domain in parsed.netloc for domain in ("youtube.com", "youtu.be")):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")
    if "youtu.be" in parsed.netloc:
        video_id = parsed.path.strip("/")
        if not video_id:
            raise HTTPException(status_code=400, detail="Invalid YouTube URL")
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


def _category_for_file(filename: str, mime: str) -> str:
    lower_name = filename.lower()
    normalized_mime = (mime or "application/octet-stream").split(";")[0].strip().lower()
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


@router.post("")
async def upload_file(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Upload a file and enqueue ingestion."""
    file_id = uuid.uuid4()
    staging_path = _staging_path(file_id)
    staging_path.parent.mkdir(parents=True, exist_ok=True)

    digest = sha256()
    size = 0

    try:
        with staging_path.open("wb") as target:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_FILE_BYTES:
                    raise HTTPException(status_code=413, detail="File too large")
                digest.update(chunk)
                target.write(chunk)

        mime_original = file.content_type or "application/octet-stream"
        mime_original = mime_original.split(";")[0].strip().lower()
        if not mime_original:
            mime_original = "application/octet-stream"
        FileIngestionService.create_ingestion(
            db,
            user_id,
            filename_original=file.filename or "upload",
            mime_original=mime_original,
            size_bytes=size,
            sha256=digest.hexdigest(),
            file_id=file_id,
        )
    except HTTPException:
        _safe_cleanup(staging_path)
        raise
    except Exception as exc:
        logger.exception("Ingestion upload failed")
        _safe_cleanup(staging_path)
        raise HTTPException(status_code=500, detail="Upload failed") from exc

    return {"file_id": str(file_id)}


@router.post("/youtube")
async def ingest_youtube(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Create an ingestion job for a YouTube video URL."""
    url = str(request.get("url", "")).strip()
    if not url:
        raise HTTPException(status_code=400, detail="YouTube URL is required")
    normalized_url = _normalize_youtube_url(url)
    video_id = _extract_youtube_id(normalized_url)
    metadata = {
        "provider": "youtube",
        "video_id": video_id,
    }
    record, _ = FileIngestionService.create_ingestion(
        db,
        user_id,
        filename_original="YouTube video",
        mime_original="video/youtube",
        size_bytes=0,
        sha256=None,
        source_url=normalized_url,
        source_metadata=metadata,
    )
    return {"file_id": str(record.id)}


@router.get("")
async def list_ingestions(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """List ingestion records for the current user."""
    records = (
        db.query(IngestedFile)
        .filter(
            IngestedFile.user_id == user_id,
            IngestedFile.deleted_at.is_(None),
        )
        .order_by(IngestedFile.created_at.desc())
        .limit(50)
        .all()
    )

    items = []
    for record in records:
        job = FileIngestionService.get_job(db, record.id)
        derivatives = FileIngestionService.list_derivatives(db, record.id)
        derivative_payload = [
            {
                "id": str(item.id),
                "kind": item.kind,
                "storage_key": item.storage_key,
                "mime": item.mime,
                "size_bytes": item.size_bytes,
            }
            for item in derivatives
        ]
        derivative_payload = _filter_user_derivatives(derivative_payload, record.user_id)
        items.append(
            {
                "file": {
                    "id": str(record.id),
                    "filename_original": record.filename_original,
                    "mime_original": record.mime_original,
                    "size_bytes": record.size_bytes,
                "sha256": record.sha256,
                "source_url": record.source_url,
                "source_metadata": record.source_metadata,
                "pinned": record.pinned,
                "category": _category_for_file(record.filename_original, record.mime_original),
                "created_at": record.created_at.isoformat(),
                },
                "job": {
                    "status": job.status if job else None,
                    "stage": job.stage if job else None,
                    "error_code": job.error_code if job else None,
                    "error_message": job.error_message if job else None,
                    "user_message": _user_message_for_error(
                        job.error_code if job else None,
                        job.status if job else None,
                    ),
                    "attempts": job.attempts if job else 0,
                    "updated_at": job.updated_at.isoformat() if job and job.updated_at else None,
                },
                "recommended_viewer": _recommended_viewer(derivative_payload, record),
            }
        )

    return {"items": items}


@router.get("/{file_id}/meta")
async def get_file_meta(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return ingestion metadata for a file."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc

    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    record.last_opened_at = datetime.now(timezone.utc)
    db.commit()

    job = FileIngestionService.get_job(db, file_uuid)
    derivatives = [
        {
            "id": str(item.id),
            "kind": item.kind,
            "storage_key": item.storage_key,
            "mime": item.mime,
            "size_bytes": item.size_bytes,
        }
        for item in FileIngestionService.list_derivatives(db, file_uuid)
    ]
    derivatives = _filter_user_derivatives(derivatives, record.user_id)

    return {
        "file": {
            "id": str(record.id),
            "filename_original": record.filename_original,
            "mime_original": record.mime_original,
            "size_bytes": record.size_bytes,
            "sha256": record.sha256,
            "source_url": record.source_url,
            "source_metadata": record.source_metadata,
            "pinned": record.pinned,
            "category": _category_for_file(record.filename_original, record.mime_original),
            "created_at": record.created_at.isoformat(),
        },
        "job": {
            "status": job.status if job else None,
            "stage": job.stage if job else None,
            "error_code": job.error_code if job else None,
            "error_message": job.error_message if job else None,
            "user_message": _user_message_for_error(
                job.error_code if job else None,
                job.status if job else None,
            ),
            "attempts": job.attempts if job else 0,
            "updated_at": job.updated_at.isoformat() if job and job.updated_at else None,
        },
        "derivatives": derivatives,
        "recommended_viewer": _recommended_viewer(derivatives, record),
    }


@router.get("/{file_id}/content")
async def get_derivative_content(
    file_id: str,
    kind: str,
    request: Request,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Stream a derivative asset for viewing."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc

    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    derivative = FileIngestionService.get_derivative(db, file_uuid, kind)
    if not derivative:
        raise HTTPException(status_code=404, detail="Derivative not found")

    storage = get_storage_backend()
    headers = {"Content-Disposition": "inline"}
    if derivative.mime == "application/pdf":
        headers["Accept-Ranges"] = "bytes"
        range_header = request.headers.get("range")
        if range_header and range_header.startswith("bytes="):
            range_value = range_header.replace("bytes=", "")
            start_str, end_str = (range_value.split("-", 1) + [""])[:2]
            if start_str.isdigit():
                total = derivative.size_bytes or 0
                start = int(start_str)
                end = int(end_str) if end_str.isdigit() else max(total - 1, start)
                if total <= 0 or start > end or end >= total:
                    raise HTTPException(status_code=416, detail="Invalid range")
                content = storage.get_object_range(derivative.storage_key, start, end)
                headers["Content-Range"] = f"bytes {start}-{end}/{total}"
                headers["Content-Length"] = str(end - start + 1)
                return Response(
                    content,
                    status_code=206,
                    media_type=derivative.mime,
                    headers=headers,
                )

    content = storage.get_object(derivative.storage_key)
    return Response(content, media_type=derivative.mime, headers=headers)


@router.post("/{file_id}/pause")
async def pause_processing(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Pause a processing job."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc
    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")
    job = FileIngestionService.update_job_status(db, file_uuid, status="paused")
    return {"status": job.status if job else "paused"}


@router.post("/{file_id}/resume")
async def resume_processing(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Resume a paused processing job."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc
    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")
    job = FileIngestionService.update_job_status(db, file_uuid, status="queued")
    return {"status": job.status if job else "queued"}


@router.post("/{file_id}/cancel")
async def cancel_processing(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Cancel processing and cleanup staged artifacts."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc
    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    job = FileIngestionService.update_job_status(db, file_uuid, status="canceled", stage="canceled")
    _safe_cleanup(_staging_path(file_uuid))
    return {"status": job.status if job else "canceled"}


@router.patch("/{file_id}/pin")
async def update_pin(
    file_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Pin or unpin an ingested file."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc
    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    pinned = bool(request.get("pinned", False))
    FileIngestionService.update_pinned(db, user_id, file_uuid, pinned)
    return {"success": True}


@router.patch("/{file_id}/rename")
async def rename_file(
    file_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Rename an ingested file."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc
    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    new_name = str(request.get("filename", "")).strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="filename is required")

    FileIngestionService.update_filename(db, user_id, file_uuid, new_name)
    return {"success": True, "filename": new_name}


@router.delete("/{file_id}")
async def delete_file(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Soft-delete an ingested file if processing is complete."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc
    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    job = FileIngestionService.get_job(db, file_uuid)
    if job and job.status not in {"ready", "failed", "canceled"}:
        raise HTTPException(status_code=409, detail="File is still processing")

    derivatives = FileIngestionService.list_derivatives(db, file_uuid)
    storage = get_storage_backend()
    for derivative in derivatives:
        try:
            storage.delete_object(derivative.storage_key)
        except Exception as exc:
            raise HTTPException(status_code=500, detail="Failed to delete file data") from exc
    FileIngestionService.delete_derivatives(db, file_uuid)
    FileIngestionService.soft_delete_file(db, file_uuid)
    _safe_cleanup(_staging_path(file_uuid))
    return {"status": "deleted"}
