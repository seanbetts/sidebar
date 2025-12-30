"""File ingestion router for uploads and processing status."""
from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import shutil
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.file_ingestion_service import FileIngestionService
from api.services.storage.service import get_storage_backend
from api.models.file_ingestion import IngestedFile


router = APIRouter(prefix="/ingestion", tags=["ingestion"])

MAX_FILE_BYTES = 100 * 1024 * 1024
STAGING_ROOT = Path("/tmp/sidebar-ingestion")


def _staging_path(file_id: uuid.UUID) -> Path:
    return STAGING_ROOT / str(file_id) / "source"


def _safe_cleanup(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path.parent, ignore_errors=True)


def _recommended_viewer(derivatives: list[dict]) -> str | None:
    kinds = {item["kind"] for item in derivatives}
    if "viewer_pdf" in kinds:
        return "viewer_pdf"
    if "image_original" in kinds:
        return "image_original"
    return None


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

        FileIngestionService.create_ingestion(
            db,
            user_id,
            filename_original=file.filename or "upload",
            mime_original=file.content_type or "application/octet-stream",
            size_bytes=size,
            sha256=digest.hexdigest(),
            file_id=file_id,
        )
    except HTTPException:
        _safe_cleanup(staging_path)
        raise
    except Exception as exc:
        _safe_cleanup(staging_path)
        raise HTTPException(status_code=500, detail="Upload failed") from exc

    return {"file_id": str(file_id)}


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
        items.append(
            {
                "file": {
                    "id": str(record.id),
                    "filename_original": record.filename_original,
                    "mime_original": record.mime_original,
                    "size_bytes": record.size_bytes,
                    "sha256": record.sha256,
                    "created_at": record.created_at.isoformat(),
                },
                "job": {
                    "status": job.status if job else None,
                    "stage": job.stage if job else None,
                    "error_code": job.error_code if job else None,
                    "error_message": job.error_message if job else None,
                    "attempts": job.attempts if job else 0,
                    "updated_at": job.updated_at.isoformat() if job and job.updated_at else None,
                },
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

    return {
        "file": {
            "id": str(record.id),
            "filename_original": record.filename_original,
            "mime_original": record.mime_original,
            "size_bytes": record.size_bytes,
            "sha256": record.sha256,
            "created_at": record.created_at.isoformat(),
        },
        "job": {
            "status": job.status if job else None,
            "stage": job.stage if job else None,
            "error_code": job.error_code if job else None,
            "error_message": job.error_message if job else None,
            "attempts": job.attempts if job else 0,
            "updated_at": job.updated_at.isoformat() if job and job.updated_at else None,
        },
        "derivatives": derivatives,
        "recommended_viewer": _recommended_viewer(derivatives),
    }


@router.get("/{file_id}/content")
async def get_derivative_content(
    file_id: str,
    kind: str,
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
    content = storage.get_object(derivative.storage_key)
    return Response(
        content,
        media_type=derivative.mime,
        headers={"Content-Disposition": "inline"},
    )


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


@router.post("/{file_id}/reprocess")
async def reprocess_file(
    file_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Requeue a file for processing."""
    try:
        file_uuid = uuid.UUID(file_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid file_id") from exc
    record = FileIngestionService.get_file(db, user_id, file_uuid)
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    job = FileIngestionService.update_job_status(
        db,
        file_uuid,
        status="queued",
        stage="queued",
        error_code=None,
        error_message=None,
    )
    return {"status": job.status if job else "queued"}


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

    FileIngestionService.soft_delete_file(db, file_uuid)
    return {"status": "deleted"}
