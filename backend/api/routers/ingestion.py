"""File ingestion router for uploads and processing status."""
from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import Response, JSONResponse
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import (
    BadRequestError,
    ConflictError,
    InternalServerError,
    NotFoundError,
    RangeNotSatisfiableError,
)
from api.services.file_ingestion_service import FileIngestionService
from api.services.storage.service import get_storage_backend
from api.routers.ingestion_helpers import (
    _category_for_file,
    _extract_youtube_id,
    _filter_user_derivatives,
    _handle_upload,
    _normalize_youtube_url,
    _recommended_viewer,
    _safe_cleanup,
    _staging_path,
    _user_message_for_error,
)
from api.utils.validation import parse_uuid


router = APIRouter(prefix="/ingestion", tags=["ingestion"])


@router.post("")
async def upload_file(
    file: UploadFile = File(...),
    folder: str = Form(default=""),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Upload a file and enqueue ingestion."""
    file_id, _ = await _handle_upload(file, folder, user_id, db)
    return {"file_id": str(file_id)}


@router.post("/quick-upload")
async def quick_upload_file(
    file: UploadFile = File(...),
    folder: str = Form(default=""),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Upload a file and enqueue ingestion (async)."""
    file_id, job_id = await _handle_upload(file, folder, user_id, db)
    return JSONResponse(
        status_code=202,
        content={"success": True, "data": {"file_id": str(file_id), "job_id": str(job_id)}},
    )


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
        raise BadRequestError("YouTube URL is required")
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
    records = FileIngestionService.list_ingestions(db, user_id, limit=50)

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
                    "path": record.path,
                    "mime_original": record.mime_original,
                    "size_bytes": record.size_bytes,
                    "sha256": record.sha256,
                    "source_url": record.source_url,
                    "source_metadata": record.source_metadata,
                    "pinned": record.pinned,
                    "pinned_order": record.pinned_order,
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
    file_id: UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return ingestion metadata for a file."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))

    record.last_opened_at = datetime.now(timezone.utc)
    db.commit()

    job = FileIngestionService.get_job(db, file_id)
    derivatives = [
        {
            "id": str(item.id),
            "kind": item.kind,
            "storage_key": item.storage_key,
            "mime": item.mime,
            "size_bytes": item.size_bytes,
        }
        for item in FileIngestionService.list_derivatives(db, file_id)
    ]
    derivatives = _filter_user_derivatives(derivatives, record.user_id)

    return {
        "file": {
            "id": str(record.id),
            "filename_original": record.filename_original,
            "path": record.path,
            "mime_original": record.mime_original,
            "size_bytes": record.size_bytes,
            "sha256": record.sha256,
            "source_url": record.source_url,
            "source_metadata": record.source_metadata,
            "pinned": record.pinned,
            "pinned_order": record.pinned_order,
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
    file_id: UUID,
    kind: str,
    request: Request,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Stream a derivative asset for viewing."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))

    derivative = FileIngestionService.get_derivative(db, file_id, kind)
    if not derivative:
        raise NotFoundError("Derivative", kind)

    # Release DB connection before fetching from storage.
    db.close()

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
                    raise RangeNotSatisfiableError("Invalid range")
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
    file_id: UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Pause a processing job."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))
    job = FileIngestionService.update_job_status(db, file_id, status="paused")
    return {"status": job.status if job else "paused"}


@router.post("/{file_id}/resume")
async def resume_processing(
    file_id: UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Resume a paused processing job."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))
    job = FileIngestionService.update_job_status(db, file_id, status="queued")
    return {"status": job.status if job else "queued"}


@router.post("/{file_id}/cancel")
async def cancel_processing(
    file_id: UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Cancel processing and cleanup staged artifacts."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))

    job = FileIngestionService.update_job_status(
        db,
        file_id,
        status="canceled",
        stage="canceled",
    )
    _safe_cleanup(_staging_path(file_id))
    return {"status": job.status if job else "canceled"}


@router.patch("/{file_id}/pin")
async def update_pin(
    file_id: UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Pin or unpin an ingested file."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))

    pinned = bool(request.get("pinned", False))
    FileIngestionService.update_pinned(db, user_id, file_id, pinned)
    return {"success": True}


@router.patch("/pinned-order")
async def update_pinned_order(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update pinned order for files."""
    order = request.get("order", [])
    if not isinstance(order, list):
        raise BadRequestError("order must be a list")
    file_ids: list[UUID] = []
    for item in order:
        file_ids.append(parse_uuid(item, "file", "id"))

    FileIngestionService.update_pinned_order(db, user_id, file_ids)
    return {"success": True}


@router.patch("/{file_id}/rename")
async def rename_file(
    file_id: UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Rename an ingested file."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))

    new_name = str(request.get("filename", "")).strip()
    if not new_name:
        raise BadRequestError("filename is required")

    FileIngestionService.update_filename(db, user_id, file_id, new_name)
    return {"success": True, "filename": new_name}


@router.delete("/{file_id}")
async def delete_file(
    file_id: UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Soft-delete an ingested file if processing is complete."""
    record = FileIngestionService.get_file(db, user_id, file_id)
    if not record:
        raise NotFoundError("File", str(file_id))

    job = FileIngestionService.get_job(db, file_id)
    if job and job.status not in {"ready", "failed", "canceled"}:
        raise ConflictError("File is still processing")

    derivatives = FileIngestionService.list_derivatives(db, file_id)
    storage = get_storage_backend()
    for derivative in derivatives:
        try:
            storage.delete_object(derivative.storage_key)
        except Exception as exc:
            raise InternalServerError("Failed to delete file data") from exc
    FileIngestionService.delete_derivatives(db, file_id)
    FileIngestionService.soft_delete_file(db, file_id)
    _safe_cleanup(_staging_path(file_id))
    return {"status": "deleted"}
