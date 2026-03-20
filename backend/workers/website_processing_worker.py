"""Website processing worker with leasing and heartbeat."""

from __future__ import annotations

import logging
import time
import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from threading import Event, Thread

from api.config import settings
from api.db.session import SessionLocal
from api.models.website_processing_job import WebsiteProcessingJob
from api.services.script_sentry import initialize_script_sentry
from api.services.web_save_error_service import classify_web_save_result
from api.services.website_processing_service import WebsiteProcessingService
from sqlalchemy import and_, or_, text

logger = logging.getLogger(__name__)


def _now() -> datetime:
    """Return current UTC time."""
    return datetime.now(UTC)


def _set_worker_scope(db) -> None:
    """Set session GUCs for cross-user worker access."""
    db.execute(text("SELECT set_config('app.user_id', '', false)"))
    db.execute(text("SELECT set_config('app.website_worker_scope', 'all', false)"))


def _claim_job(db, worker_id: str) -> WebsiteProcessingJob | None:
    """Atomically claim a queued job."""
    job = (
        db.query(WebsiteProcessingJob)
        .filter(
            and_(
                WebsiteProcessingJob.status == "queued",
                or_(
                    WebsiteProcessingJob.lease_expires_at.is_(None),
                    WebsiteProcessingJob.lease_expires_at < _now(),
                ),
            )
        )
        .order_by(WebsiteProcessingJob.created_at.asc())
        .with_for_update(skip_locked=True)
        .first()
    )
    if not job:
        return None

    job.status = "processing"
    job.worker_id = worker_id
    job.lease_expires_at = _now() + timedelta(
        seconds=settings.website_worker_lease_seconds
    )
    job.updated_at = _now()
    db.commit()
    logger.info("Claimed job %s (url=%s)", job.id, job.url)
    return job


def _refresh_lease(db, job: WebsiteProcessingJob) -> None:
    """Extend the lease on a job."""
    job.lease_expires_at = _now() + timedelta(
        seconds=settings.website_worker_lease_seconds
    )
    job.updated_at = _now()
    db.commit()


def _start_heartbeat(
    job_id: uuid.UUID,
    user_id: str,
) -> Callable[[], None]:
    """Start a heartbeat thread that renews the lease periodically."""
    stop_event = Event()

    def _beat() -> None:
        with SessionLocal() as heartbeat_db:
            _set_worker_scope(heartbeat_db)
            while not stop_event.is_set():
                job = (
                    heartbeat_db.query(WebsiteProcessingJob)
                    .filter(WebsiteProcessingJob.id == job_id)
                    .first()
                )
                if not job or job.status != "processing":
                    break
                _refresh_lease(heartbeat_db, job)
                stop_event.wait(settings.website_worker_heartbeat_seconds)

    thread = Thread(target=_beat, daemon=True)
    thread.start()

    def _stop() -> None:
        stop_event.set()
        thread.join(timeout=settings.website_worker_heartbeat_seconds)

    return _stop


def _requeue_stalled_jobs(db) -> None:
    """Reset jobs with expired leases back to queued."""
    stalled = (
        db.query(WebsiteProcessingJob)
        .filter(
            and_(
                WebsiteProcessingJob.status == "processing",
                WebsiteProcessingJob.lease_expires_at.is_not(None),
                WebsiteProcessingJob.lease_expires_at < _now(),
            )
        )
        .limit(5)
        .all()
    )
    for job in stalled:
        logger.warning("Requeuing stalled job %s (url=%s)", job.id, job.url)
        job.status = "queued"
        job.worker_id = None
        job.lease_expires_at = None
        job.updated_at = _now()
    if stalled:
        db.commit()


def _process_job(db, job: WebsiteProcessingJob) -> None:
    """Run the web-save script for a job and update status.

    NOTE: No explicit Realtime broadcast needed here.
    The save script inserts into the ``websites`` table, which triggers
    Supabase Postgres Realtime automatically. iOS/web clients subscribe
    to both the websites table (for successes) and the
    website_processing_jobs table (for failures).
    """
    import asyncio

    from api.services.agent.skills.executor import SkillExecutor

    executor = SkillExecutor(settings)
    try:
        result = asyncio.run(
            executor.execute(
                "web-save",
                "save_url.py",
                [job.url, "--database", "--user-id", job.user_id],
                user_id=job.user_id,
                env_overrides={
                    "SKILL_TIMEOUT_SECONDS": str(settings.website_save_timeout_seconds),
                },
            )
        )
    except Exception as exc:
        logger.exception("Job %s failed with exception", job.id)
        WebsiteProcessingService.update_job(
            db, job.id, status="failed", error_message=str(exc)
        )
        return

    if not result.get("success"):
        normalized_error = classify_web_save_result(
            result, url=job.url, target_url=job.url
        )
        error_msg = normalized_error.get(
            "message", result.get("error", "Unknown error")
        )
        logger.error("Job %s failed: %s", job.id, error_msg)
        WebsiteProcessingService.update_job(
            db, job.id, status="failed", error_message=error_msg
        )
        return

    raw_website_id = str((result.get("data") or {}).get("id") or "").strip()
    if not raw_website_id:
        WebsiteProcessingService.update_job(
            db,
            job.id,
            status="failed",
            error_message="No website ID returned",
        )
        return

    try:
        website_uuid = uuid.UUID(raw_website_id)
    except ValueError:
        WebsiteProcessingService.update_job(
            db,
            job.id,
            status="failed",
            error_message="Invalid website ID returned",
        )
        return

    WebsiteProcessingService.update_job(
        db, job.id, status="completed", website_id=website_uuid
    )
    logger.info("Job %s completed (website_id=%s)", job.id, raw_website_id)


def _run_worker_loop(worker_id: str) -> None:
    """Main worker loop: poll, claim, process."""
    logger.info("Website worker %s starting", worker_id)

    while True:
        try:
            with SessionLocal() as db:
                _set_worker_scope(db)
                _requeue_stalled_jobs(db)

                job = _claim_job(db, worker_id)
                if not job:
                    time.sleep(settings.website_worker_poll_seconds)
                    continue

                stop_heartbeat = _start_heartbeat(job.id, job.user_id)
                try:
                    _process_job(db, job)
                finally:
                    stop_heartbeat()
        except Exception:
            logger.exception("Worker loop error")
            time.sleep(settings.website_worker_poll_seconds)


def main() -> None:
    """Entry point for the website processing worker."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    initialize_script_sentry()

    worker_id = f"web-worker-{uuid.uuid4().hex[:8]}"
    concurrency = settings.website_worker_concurrency

    if concurrency <= 1:
        _run_worker_loop(worker_id)
    else:
        from concurrent.futures import ThreadPoolExecutor

        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = []
            for i in range(concurrency):
                thread_worker_id = f"{worker_id}-t{i}"
                futures.append(pool.submit(_run_worker_loop, thread_worker_id))
            for f in futures:
                f.result()


if __name__ == "__main__":
    main()
