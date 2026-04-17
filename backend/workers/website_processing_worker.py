"""Website processing worker with leasing and heartbeat."""

from __future__ import annotations

import logging
import time
import uuid
from collections.abc import Callable
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from threading import Event, Thread

from sqlalchemy import and_, or_
from sqlalchemy.orm.attributes import flag_modified

from api.config import settings
from api.db.session import SessionLocal, set_website_worker_scope
from api.models.website import Website
from api.models.website_processing_job import WebsiteProcessingJob
from api.services.script_sentry import initialize_script_sentry
from api.services.web_save_error_service import classify_web_save_result
from api.services.website_processing_service import WebsiteProcessingService
from api.services.websites_service import WebsitesService

logger = logging.getLogger(__name__)

_CLEANUP_INTERVAL_SECONDS = 3600
_JOB_RETENTION_DAYS = 7


def _now() -> datetime:
    """Return current UTC time."""
    return datetime.now(UTC)


def _set_worker_scope(db) -> None:
    """Set session GUCs for cross-user worker access."""
    set_website_worker_scope(db, enabled=True)


def _snapshot_website_state(website: Website | None) -> dict[str, object] | None:
    """Capture the mutable website fields so canceled runs can be rolled back."""
    if website is None:
        return None

    return {
        "id": website.id,
        "user_id": website.user_id,
        "url": website.url,
        "url_full": website.url_full,
        "domain": website.domain,
        "title": website.title,
        "content": website.content,
        "source": website.source,
        "saved_at": website.saved_at,
        "published_at": website.published_at,
        "reading_time": website.reading_time,
        "metadata_": deepcopy(website.metadata_ or {}),
        "is_archived": website.is_archived,
        "updated_at": website.updated_at,
        "last_opened_at": website.last_opened_at,
        "deleted_at": website.deleted_at,
    }


def _restore_website_state(db, snapshot: dict[str, object] | None) -> bool:
    """Restore a pre-run website snapshot after a canceled repeated save."""
    if snapshot is None:
        return False

    website = (
        db.query(Website)
        .filter(
            Website.user_id == snapshot["user_id"],
            Website.id == snapshot["id"],
        )
        .first()
    )
    if website is None:
        return False

    website.url = str(snapshot["url"])
    website.url_full = snapshot["url_full"]
    website.domain = str(snapshot["domain"])
    website.title = str(snapshot["title"])
    website.content = str(snapshot["content"])
    website.source = snapshot["source"]
    website.saved_at = snapshot["saved_at"]
    website.published_at = snapshot["published_at"]
    website.reading_time = snapshot["reading_time"]
    website.metadata_ = deepcopy(snapshot["metadata_"])
    website.is_archived = bool(snapshot["is_archived"])
    website.updated_at = snapshot["updated_at"]
    website.last_opened_at = snapshot["last_opened_at"]
    website.deleted_at = snapshot["deleted_at"]
    flag_modified(website, "metadata_")
    db.commit()
    return True


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


def _cleanup_old_jobs(db) -> int:
    """Delete completed/failed jobs older than retention period."""
    cutoff = _now() - timedelta(days=_JOB_RETENTION_DAYS)
    deleted = (
        db.query(WebsiteProcessingJob)
        .filter(
            and_(
                WebsiteProcessingJob.status.in_(["completed", "failed"]),
                WebsiteProcessingJob.updated_at < cutoff,
            )
        )
        .delete(synchronize_session="fetch")
    )
    if deleted:
        db.commit()
        logger.info("Cleaned up %d old website jobs", deleted)
    return deleted


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


def _compute_idle_poll_seconds(idle_polls: int) -> int:
    """Keep website polling responsive because saves are user-initiated."""
    _ = idle_polls
    return max(settings.website_worker_poll_seconds, 1)


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

    job_id = job.id
    job_user_id = job.user_id
    job_url = job.url
    db.refresh(job)
    if job.status == "canceled":
        logger.info("Skipping canceled job %s before execution", job.id)
        return
    existing_website_snapshot = _snapshot_website_state(
        WebsitesService.get_by_url(
            db,
            job_user_id,
            job_url,
            include_deleted=True,
        )
    )
    # End the preflight read transaction before the external save work begins.
    # Otherwise the worker can sit idle in transaction while waiting on I/O.
    if db.in_transaction():
        db.rollback()

    try:
        executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
        result = asyncio.run(
            executor.execute(
                "web-save",
                "save_url.py",
                [job_url, "--database", "--user-id", job_user_id],
                user_id=job_user_id,
                env_overrides={
                    "SKILL_TIMEOUT_SECONDS": str(settings.website_save_timeout_seconds),
                },
            )
        )
    except Exception as exc:
        logger.exception("Job %s failed with exception", job_id)
        WebsiteProcessingService.update_job(
            db, job_id, status="failed", error_message=str(exc)
        )
        return

    if not result.get("success"):
        normalized_error = classify_web_save_result(
            result, url=job_url, target_url=job_url
        )
        error_msg = normalized_error.get(
            "message", result.get("error", "Unknown error")
        )
        logger.error("Job %s failed: %s", job_id, error_msg)
        WebsiteProcessingService.update_job(
            db, job_id, status="failed", error_message=error_msg
        )
        return

    raw_website_id = str((result.get("data") or {}).get("id") or "").strip()
    if not raw_website_id:
        WebsiteProcessingService.update_job(
            db,
            job_id,
            status="failed",
            error_message="No website ID returned",
        )
        return

    try:
        website_uuid = uuid.UUID(raw_website_id)
    except ValueError:
        WebsiteProcessingService.update_job(
            db,
            job_id,
            status="failed",
            error_message="Invalid website ID returned",
        )
        return

    db.refresh(job)
    if job.status == "canceled":
        if (
            existing_website_snapshot
            and existing_website_snapshot["id"] == website_uuid
        ):
            _restore_website_state(db, existing_website_snapshot)
            logger.info(
                "Job %s finished after cancellation; restored website_id=%s",
                job_id,
                raw_website_id,
            )
        else:
            WebsitesService.soft_delete_website(
                db,
                job_user_id,
                website_uuid,
                allow_missing=True,
            )
            logger.info(
                "Job %s finished after cancellation; soft-deleted website_id=%s",
                job_id,
                raw_website_id,
            )
        return

    WebsiteProcessingService.update_job(
        db, job_id, status="completed", website_id=website_uuid
    )
    logger.info("Job %s completed (website_id=%s)", job_id, raw_website_id)


def _run_worker_loop(worker_id: str) -> None:
    """Main worker loop: poll, claim, process."""
    logger.info("Website worker %s starting", worker_id)
    last_cleanup = 0.0
    idle_polls = 0

    while True:
        try:
            with SessionLocal() as db:
                _set_worker_scope(db)
                now_ts = time.monotonic()
                if now_ts - last_cleanup >= _CLEANUP_INTERVAL_SECONDS:
                    _cleanup_old_jobs(db)
                    last_cleanup = now_ts
                _requeue_stalled_jobs(db)

                job = _claim_job(db, worker_id)
                if not job:
                    if db.in_transaction():
                        db.rollback()
                    idle_polls += 1
                    time.sleep(_compute_idle_poll_seconds(idle_polls))
                    continue

                idle_polls = 0
                stop_heartbeat = _start_heartbeat(job.id, job.user_id)
                try:
                    _process_job(db, job)
                finally:
                    stop_heartbeat()
        except Exception:
            logger.exception("Worker loop error")
            idle_polls = 0
            time.sleep(settings.website_worker_poll_seconds)


def main() -> None:
    """Entry point for the website processing worker."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    initialize_script_sentry(
        "workers.website_processing_worker",
        process_type="worker",
    )

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
