"""Ingestion worker loop with leasing and stage updates."""
from __future__ import annotations

import io
import os
import time
import subprocess
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from pathlib import Path
import shutil
from uuid import uuid4

from sqlalchemy import and_, or_, text

from PIL import Image
from pypdf import PdfReader
from pptx import Presentation
from docx import Document
from openpyxl import load_workbook

from api.db.session import SessionLocal
from api.models.file_ingestion import FileProcessingJob, IngestedFile, FileDerivative
from api.config import settings
from api.services.storage.service import get_storage_backend


LEASE_SECONDS = 180
SLEEP_SECONDS = 2
MAX_ATTEMPTS = 3
BACKOFF_BASE_SECONDS = 2
BACKOFF_MAX_SECONDS = 60
PIPELINE_STAGES = [
    "validating",
    "converting",
    "extracting",
    "ai_md",
    "thumb",
    "finalizing",
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


@dataclass(frozen=True)
class DerivativePayload:
    kind: str
    storage_key: str
    mime: str
    size_bytes: int
    sha256: str | None
    content: bytes


class IngestionError(Exception):
    def __init__(self, code: str, message: str, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.retryable = retryable


def _claim_job(db, worker_id: str) -> FileProcessingJob | None:
    job = (
        db.query(FileProcessingJob)
        .filter(
            and_(
                FileProcessingJob.status == "queued",
                or_(
                    FileProcessingJob.lease_expires_at.is_(None),
                    FileProcessingJob.lease_expires_at < _now(),
                ),
            )
        )
        .order_by(FileProcessingJob.updated_at.asc())
        .with_for_update(skip_locked=True)
        .first()
    )
    if not job:
        return None

    job.status = "processing"
    job.stage = "validating"
    job.worker_id = worker_id
    job.lease_expires_at = _now() + timedelta(seconds=LEASE_SECONDS)
    job.started_at = job.started_at or _now()
    job.updated_at = _now()
    db.commit()
    return job


def _refresh_lease(db, job: FileProcessingJob) -> None:
    job.lease_expires_at = _now() + timedelta(seconds=LEASE_SECONDS)
    job.updated_at = _now()
    db.commit()


def _set_stage(db, job: FileProcessingJob, stage: str) -> None:
    job.stage = stage
    job.updated_at = _now()
    db.commit()


def _mark_ready(db, job: FileProcessingJob) -> None:
    job.status = "ready"
    job.stage = "ready"
    job.finished_at = _now()
    job.updated_at = _now()
    job.worker_id = None
    job.lease_expires_at = None
    db.commit()


def _compute_backoff_seconds(attempts: int) -> int:
    if attempts <= 0:
        return 0
    delay = BACKOFF_BASE_SECONDS * (2 ** (attempts - 1))
    return min(delay, BACKOFF_MAX_SECONDS)


def _retry_or_fail(db, job: FileProcessingJob, error: IngestionError) -> None:
    job.attempts = (job.attempts or 0) + 1
    job.error_code = error.code
    job.error_message = str(error)
    job.updated_at = _now()
    job.worker_id = None
    job.lease_expires_at = None

    if error.retryable and job.attempts < MAX_ATTEMPTS:
        job.status = "queued"
        job.stage = "queued"
        job.lease_expires_at = _now() + timedelta(seconds=_compute_backoff_seconds(job.attempts))
        db.commit()
        return

    job.status = "failed"
    job.stage = "failed"
    job.finished_at = _now()
    db.commit()


def _requeue_stalled_jobs(db) -> None:
    stalled_jobs = (
        db.query(FileProcessingJob)
        .filter(
            and_(
                FileProcessingJob.status == "processing",
                FileProcessingJob.lease_expires_at.is_not(None),
                FileProcessingJob.lease_expires_at < _now(),
            )
        )
        .order_by(FileProcessingJob.updated_at.asc())
        .limit(5)
        .all()
    )
    for job in stalled_jobs:
        _retry_or_fail(
            db,
            job,
            IngestionError("WORKER_STALLED", "Worker heartbeat expired", retryable=True),
        )


def _get_file(db, job: FileProcessingJob) -> IngestedFile:
    record = db.query(IngestedFile).filter(IngestedFile.id == job.file_id).first()
    if not record:
        raise IngestionError("FILE_NOT_FOUND", "Ingestion record missing", retryable=False)
    return record


def _staging_path(file_id: str) -> Path:
    return Path("/tmp/sidebar-ingestion") / file_id / "source"


def _cleanup_staging(file_id: str) -> None:
    staging_root = Path("/tmp/sidebar-ingestion") / file_id
    if staging_root.exists():
        shutil.rmtree(staging_root, ignore_errors=True)


def _derivative_dir(file_id: str) -> Path:
    return Path("/tmp/sidebar-ingestion") / file_id / "derived"


def _detect_extension(filename: str, mime: str) -> str:
    suffix = Path(filename).suffix
    if suffix:
        return suffix
    if mime == "image/png":
        return ".png"
    if mime in {"image/jpeg", "image/jpg"}:
        return ".jpg"
    return ""


def _run_libreoffice_convert(source_path: Path, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    command = [
        "soffice",
        "--headless",
        "--convert-to",
        "pdf",
        "--outdir",
        str(output_dir),
        str(source_path),
    ]
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    except FileNotFoundError as exc:
        raise IngestionError("CONVERSION_UNAVAILABLE", "LibreOffice not available", retryable=False) from exc
    except subprocess.TimeoutExpired as exc:
        raise IngestionError("CONVERSION_TIMEOUT", "Conversion timed out", retryable=True) from exc
    except subprocess.CalledProcessError as exc:
        raise IngestionError("CONVERSION_FAILED", "Conversion failed", retryable=False) from exc

    pdf_path = output_dir / (source_path.stem + ".pdf")
    if not pdf_path.exists():
        raise IngestionError("CONVERSION_FAILED", "Converted PDF missing", retryable=False)
    return pdf_path


def _generate_image_thumbnail(image_path: Path, max_size: int = 640) -> bytes | None:
    try:
        with Image.open(image_path) as image:
            image.thumbnail((max_size, max_size))
            output = io.BytesIO()
            image.save(output, format="PNG")
            return output.getvalue()
    except Exception:
        return None


def _generate_pdf_thumbnail(pdf_path: Path, output_dir: Path) -> bytes | None:
    if not shutil.which("pdftoppm"):
        return None
    output_dir.mkdir(parents=True, exist_ok=True)
    output_base = output_dir / "thumb"
    command = [
        "pdftoppm",
        "-f",
        "1",
        "-l",
        "1",
        "-singlefile",
        "-png",
        str(pdf_path),
        str(output_base),
    ]
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    except (FileNotFoundError, subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return None
    thumb_path = output_dir / "thumb.png"
    if not thumb_path.exists():
        return None
    return thumb_path.read_bytes()


def _extract_pdf_text(pdf_path: Path) -> str:
    reader = PdfReader(str(pdf_path))
    sections = []
    for index, page in enumerate(reader.pages, start=1):
        text = page.extract_text() or ""
        sections.append(f"## Page {index}\n\n{text.strip()}")
    return "\n\n".join(sections).strip()


def _extract_pptx_text(pptx_path: Path) -> str:
    presentation = Presentation(str(pptx_path))
    sections = []
    for index, slide in enumerate(presentation.slides, start=1):
        texts = []
        for shape in slide.shapes:
            if hasattr(shape, "text") and shape.text:
                texts.append(shape.text)
        content = "\n".join(texts).strip()
        sections.append(f"## Slide {index}\n\n{content}")
    return "\n\n".join(sections).strip()


def _extract_docx_text(docx_path: Path) -> str:
    document = Document(str(docx_path))
    parts: list[str] = []
    for paragraph in document.paragraphs:
        if paragraph.text:
            parts.append(paragraph.text)
    for table in document.tables:
        rows = []
        for row in table.rows:
            rows.append(" | ".join(cell.text.strip() for cell in row.cells))
        if rows:
            parts.append("\n".join(rows))
    return "\n\n".join(parts).strip()


def _extract_xlsx_text(xlsx_path: Path) -> str:
    workbook = load_workbook(str(xlsx_path), data_only=True, read_only=True)
    sections = []
    for sheet in workbook.worksheets:
        rows = []
        for row in sheet.iter_rows(min_row=1, max_row=10, values_only=True):
            rows.append(" | ".join("" if cell is None else str(cell) for cell in row))
        content = "\n".join(rows).strip()
        sections.append(f"## Sheet: {sheet.title}\n\n{content}")
    return "\n\n".join(sections).strip()


def _build_derivatives(record: IngestedFile, source_path: Path) -> list[DerivativePayload]:
    mime = record.mime_original
    file_id = str(record.id)
    user_prefix = f"{record.user_id}/files/{file_id}"
    content = source_path.read_bytes()
    extraction_text = ""
    viewer_payload: DerivativePayload | None = None
    thumb_payload: DerivativePayload | None = None
    thumb_bytes: bytes | None = None

    if mime == "application/pdf":
        viewer_payload = DerivativePayload(
            kind="viewer_pdf",
            storage_key=f"{user_prefix}/derivatives/viewer.pdf",
            mime="application/pdf",
            size_bytes=len(content),
            sha256=sha256(content).hexdigest(),
            content=content,
        )
        extraction_text = _extract_pdf_text(source_path)
        thumb_bytes = _generate_pdf_thumbnail(source_path, _derivative_dir(file_id))
    elif mime.startswith("image/"):
        extension = _detect_extension(record.filename_original, mime)
        viewer_payload = DerivativePayload(
            kind="image_original",
            storage_key=f"{user_prefix}/derivatives/image{extension or ''}",
            mime=mime,
            size_bytes=len(content),
            sha256=sha256(content).hexdigest(),
            content=content,
        )
        extraction_text = "Image file. No text extraction available."
        thumb_bytes = _generate_image_thumbnail(source_path)
    elif mime in {
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    }:
        pdf_path = _run_libreoffice_convert(source_path, _derivative_dir(file_id))
        pdf_bytes = pdf_path.read_bytes()
        viewer_payload = DerivativePayload(
            kind="viewer_pdf",
            storage_key=f"{user_prefix}/derivatives/viewer.pdf",
            mime="application/pdf",
            size_bytes=len(pdf_bytes),
            sha256=sha256(pdf_bytes).hexdigest(),
            content=pdf_bytes,
        )
        if mime.endswith("wordprocessingml.document"):
            extraction_text = _extract_docx_text(source_path)
        elif mime.endswith("presentationml.presentation"):
            extraction_text = _extract_pptx_text(source_path)
        else:
            extraction_text = _extract_xlsx_text(source_path)
        thumb_bytes = _generate_pdf_thumbnail(pdf_path, _derivative_dir(file_id))
    else:
        raise IngestionError("UNSUPPORTED_TYPE", "Unsupported file type", retryable=False)

    if viewer_payload is None:
        raise IngestionError("DERIVATIVE_MISSING", "Viewer asset missing", retryable=False)

    if thumb_bytes:
        thumb_payload = DerivativePayload(
            kind="thumb_png",
            storage_key=f"{user_prefix}/derivatives/thumb.png",
            mime="image/png",
            size_bytes=len(thumb_bytes),
            sha256=sha256(thumb_bytes).hexdigest(),
            content=thumb_bytes,
        )

    ai_body = (
        "---\n"
        f"file_id: {record.id}\n"
        f"source_filename: {record.filename_original}\n"
        f"source_mime: {record.mime_original}\n"
        f"created_at: {record.created_at.isoformat()}\n"
        f"sha256: {record.sha256}\n"
        "derivatives:\n"
        f"  {viewer_payload.kind}: true\n"
        "---\n\n"
        f"{extraction_text or 'No text extraction available.'}"
    )
    ai_bytes = ai_body.encode("utf-8")
    ai_md = DerivativePayload(
        kind="ai_md",
        storage_key=f"{user_prefix}/ai/ai.md",
        mime="text/markdown",
        size_bytes=len(ai_bytes),
        sha256=sha256(ai_bytes).hexdigest(),
        content=ai_bytes,
    )

    derivatives = [viewer_payload, ai_md]
    if thumb_payload:
        derivatives.append(thumb_payload)
    return derivatives


def worker_loop() -> None:
    worker_id = os.getenv("INGESTION_WORKER_ID") or f"worker-{uuid4()}"
    worker_user_id = os.getenv("INGESTION_WORKER_USER_ID") or settings.default_user_id
    while True:
        with SessionLocal() as db:
            db.execute(text("SET app.is_worker = 'true'"))
            if worker_user_id:
                db.execute(text("SET app.user_id = :user_id"), {"user_id": worker_user_id})
            _requeue_stalled_jobs(db)
            job = _claim_job(db, worker_id)
            if not job:
                time.sleep(SLEEP_SECONDS)
                continue

            try:
                record = _get_file(db, job)
                source_path = _staging_path(str(record.id))
                if not source_path.exists():
                    raise IngestionError("SOURCE_MISSING", "Uploaded file not found", retryable=False)

                for stage in PIPELINE_STAGES:
                    db.refresh(job)
                    if job.status in {"paused", "canceled"}:
                        raise IngestionError("JOB_HALTED", "Job halted by user", retryable=False)
                    _set_stage(db, job, stage)
                    _refresh_lease(db, job)

                    if stage == "validating":
                        if record.size_bytes <= 0:
                            raise IngestionError("FILE_EMPTY", "Uploaded file is empty", retryable=False)
                    elif stage in {"converting", "extracting", "ai_md", "thumb"}:
                        time.sleep(0.05)
                    elif stage == "finalizing":
                        derivatives = _build_derivatives(record, source_path)
                        storage = get_storage_backend()
                        for item in derivatives:
                            storage.put_object(item.storage_key, item.content, content_type=item.mime)

                        db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
                        now = _now()
                        for item in derivatives:
                            db.add(
                                FileDerivative(
                                    file_id=record.id,
                                    kind=item.kind,
                                    storage_key=item.storage_key,
                                    mime=item.mime,
                                    size_bytes=item.size_bytes,
                                    sha256=item.sha256,
                                    created_at=now,
                                )
                            )
                        db.commit()

                db.refresh(job)
                if job.status not in {"paused", "canceled"}:
                    _mark_ready(db, job)
                    _cleanup_staging(str(record.id))
            except IngestionError as error:
                if error.code == "JOB_HALTED":
                    continue
                _retry_or_fail(db, job, error)
                if job.status == "failed":
                    _cleanup_staging(str(job.file_id))
            except Exception as error:
                _retry_or_fail(db, job, IngestionError("UNKNOWN_ERROR", str(error), retryable=True))
                if job.status == "failed":
                    _cleanup_staging(str(job.file_id))


if __name__ == "__main__":
    worker_loop()
