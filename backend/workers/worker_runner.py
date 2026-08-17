"""Run always-on control workers in a single process."""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable
from functools import partial
from time import sleep

from api.services.script_sentry import initialize_script_sentry
from workers.data_retention_worker import worker_loop as data_retention_loop
from workers.notification_schedule_worker import worker_loop as notification_loop
from workers.worker_demand_monitor import worker_loop as worker_demand_loop

logger = logging.getLogger(__name__)


def _supervise(name: str, target: Callable[[], None]) -> None:
    """Restart one control loop independently after a crash or unexpected exit."""
    while True:
        try:
            target()
        except Exception:
            logger.exception("Control loop crashed", extra={"control_loop": name})
        else:
            logger.error(
                "Control loop exited unexpectedly",
                extra={"control_loop": name},
            )
        sleep(2)


def main() -> None:
    """Start notification, retention, and worker-demand supervisors."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    initialize_script_sentry("workers.worker_runner", process_type="worker")

    threads = [
        threading.Thread(
            name=name,
            target=partial(_supervise, name, target),
            daemon=True,
        )
        for name, target in (
            ("notification", partial(notification_loop, raise_on_error=True)),
            ("retention", partial(data_retention_loop, raise_on_error=True)),
            ("worker-demand", worker_demand_loop),
        )
    ]
    for thread in threads:
        thread.start()
        logger.info(
            "Control loop supervisor started",
            extra={"control_loop": thread.name},
        )

    threads[0].join()


if __name__ == "__main__":
    main()
