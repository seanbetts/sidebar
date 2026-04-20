"""Run shared background workers in a single process."""

import logging
import threading

from workers.data_retention_worker import worker_loop as data_retention_loop
from workers.ingestion_worker import worker_loop as ingestion_loop

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


def _run_data_retention() -> None:
    """Run the data retention worker loop."""
    data_retention_loop()


def main() -> None:
    """Start shared ingestion and retention workers."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    ingestion_thread = threading.Thread(target=_run_ingestion, daemon=True)
    ingestion_thread.start()
    logger.info("Ingestion worker started in background thread")

    retention_thread = threading.Thread(
        target=_run_data_retention,
        daemon=True,
    )
    retention_thread.start()
    logger.info("Data retention worker started in background thread")

    ingestion_thread.join()


if __name__ == "__main__":
    main()
