"""Run all background workers in a single process."""

import logging
import threading

from workers.ingestion_worker import worker_loop as ingestion_loop
from workers.notification_schedule_worker import worker_loop as notification_loop
from workers.website_processing_worker import main as website_main

logger = logging.getLogger(__name__)


def _run_ingestion() -> None:
    """Run the ingestion worker with crash recovery."""
    import time

    while True:
        try:
            ingestion_loop()
        except Exception:
            logger.exception("Ingestion worker crashed, restarting after delay")
            time.sleep(2)


def _run_notification_schedule() -> None:
    """Run the notification schedule worker with crash recovery."""
    import time

    while True:
        try:
            notification_loop()
        except Exception:
            logger.exception(
                "Notification schedule worker crashed, restarting after delay"
            )
            time.sleep(2)


def main() -> None:
    """Start all workers as threads in a single process."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    ingestion_thread = threading.Thread(target=_run_ingestion, daemon=True)
    ingestion_thread.start()
    logger.info("Ingestion worker started in background thread")

    notification_thread = threading.Thread(
        target=_run_notification_schedule,
        daemon=True,
    )
    notification_thread.start()
    logger.info("Notification schedule worker started in background thread")

    # Website worker runs in the main thread (it manages its own ThreadPool)
    website_main()


if __name__ == "__main__":
    main()
