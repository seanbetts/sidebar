"""Supervise durable queue demand and start existing Fly worker Machines."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, date, datetime
from time import monotonic, sleep

import sentry_sdk

from api.config import settings
from api.db.session import (
    SessionLocal,
    set_ingestion_worker_scope,
    set_website_worker_scope,
)
from api.services.fly_machine_service import (
    FlyMachineService,
    MachineStartResult,
    WorkerProcessGroup,
)
from api.services.worker_queue_demand_service import (
    WorkerQueueDemand,
    WorkerQueueDemandService,
)

logger = logging.getLogger("worker_demand.monitor")

_FIRST_FAILURE_REPORT_CYCLE = 3
_ADDITIONAL_FAILURE_REPORT_INTERVAL = 12
_TOKEN_EXPIRY_WARNING_DAYS = 30
_TOKEN_EXPIRY_SENTRY_DAYS = 7
_MISSING_TOKEN_FAILURE = "configuration:MissingFlyWorkerControlToken"
_MIN_CYCLE_SLEEP_SECONDS = 0.1


@dataclass(frozen=True, slots=True)
class DemandMonitorResult:
    """Immutable outcome of one durable queue-demand inspection cycle."""

    demand: WorkerQueueDemand
    starts: tuple[MachineStartResult, ...]
    failures: tuple[str, ...]


@dataclass(slots=True)
class _FailureTracker:
    """Bound repeated lifecycle-failure notifications while preserving logs."""

    consecutive_failed_cycles: int = 0

    def record(self, failures: tuple[str, ...]) -> None:
        """Record one cycle and notify Sentry at bounded consecutive thresholds."""
        if not failures:
            self.consecutive_failed_cycles = 0
            return

        self.consecutive_failed_cycles += 1
        if not self._should_notify():
            return

        try:
            with sentry_sdk.new_scope() as scope:
                scope.set_extra("failure_classes", failures)
                scope.set_extra(
                    "consecutive_failed_cycles",
                    self.consecutive_failed_cycles,
                )
                sentry_sdk.capture_message(
                    "Worker demand monitor failures are continuing",
                    level="error",
                )
        except Exception as exc:
            logger.error(
                "Worker demand monitor Sentry notification failed",
                extra={
                    "process_group": None,
                    "machine_id": None,
                    "result": "sentry_notification_failed",
                    "failure_class": exc.__class__.__name__,
                },
            )

    def _should_notify(self) -> bool:
        """Return whether this consecutive failure count crosses a report gate."""
        if self.consecutive_failed_cycles < _FIRST_FAILURE_REPORT_CYCLE:
            return False
        return (
            self.consecutive_failed_cycles - _FIRST_FAILURE_REPORT_CYCLE
        ) % _ADDITIONAL_FAILURE_REPORT_INTERVAL == 0


@dataclass(slots=True)
class _TokenExpiryTracker:
    """Emit each token-expiry threshold once for the configured expiry date."""

    expires_at: date | None = None
    warning_emitted: bool = False
    critical_emitted: bool = False

    def record(self, expires_at: date | None, *, today: date) -> None:
        """Log expiry diagnostics and send one seven-day Sentry warning."""
        if expires_at != self.expires_at:
            self.expires_at = expires_at
            self.warning_emitted = False
            self.critical_emitted = False
        if expires_at is None:
            return

        days_remaining = (expires_at - today).days
        if days_remaining <= _TOKEN_EXPIRY_SENTRY_DAYS:
            if self.critical_emitted:
                return
            self.critical_emitted = True
            self.warning_emitted = True
            logger.warning(
                "Fly worker control token expiry is approaching",
                extra={
                    "process_group": None,
                    "machine_id": None,
                    "result": "token_expiry_critical",
                    "failure_class": None,
                    "expires_at": expires_at.isoformat(),
                    "days_remaining": days_remaining,
                },
            )
            self._notify_sentry(days_remaining)
            return

        if days_remaining <= _TOKEN_EXPIRY_WARNING_DAYS and not self.warning_emitted:
            self.warning_emitted = True
            logger.warning(
                "Fly worker control token expiry is approaching",
                extra={
                    "process_group": None,
                    "machine_id": None,
                    "result": "token_expiry_warning",
                    "failure_class": None,
                    "expires_at": expires_at.isoformat(),
                    "days_remaining": days_remaining,
                },
            )

    @staticmethod
    def _notify_sentry(days_remaining: int) -> None:
        """Send a secret-free token-expiry warning without breaking the loop."""
        try:
            with sentry_sdk.new_scope() as scope:
                scope.set_extra("days_remaining", days_remaining)
                sentry_sdk.capture_message(
                    "Fly worker control token expires within seven days",
                    level="warning",
                )
        except Exception as exc:
            logger.error(
                "Fly token expiry Sentry notification failed",
                extra={
                    "process_group": None,
                    "machine_id": None,
                    "result": "sentry_notification_failed",
                    "failure_class": exc.__class__.__name__,
                },
            )


def execute_once(
    machine_service: FlyMachineService,
    *,
    now: datetime | None = None,
) -> DemandMonitorResult:
    """Inspect durable demand once and independently start each demanded worker."""
    with SessionLocal() as db:
        try:
            set_website_worker_scope(db, enabled=True)
            set_ingestion_worker_scope(db, enabled=True)
            demand = WorkerQueueDemandService.inspect(db, now=now)
        finally:
            db.rollback()

    starts: list[MachineStartResult] = []
    failures: list[str] = []
    groups: tuple[tuple[WorkerProcessGroup, bool], ...] = (
        ("website", demand.website),
        ("ingestion", demand.ingestion),
    )
    for process_group, demanded in groups:
        if not demanded:
            continue
        logger.info(
            "Worker queue demand detected",
            extra={
                "process_group": process_group,
                "machine_id": None,
                "result": "demand_detected",
                "failure_class": None,
            },
        )
        try:
            start = machine_service.ensure_started(process_group)
        except Exception as exc:
            failure_class = exc.__class__.__name__
            failures.append(f"{process_group}:{failure_class}")
            logger.error(
                "Worker start failed",
                extra={
                    "process_group": process_group,
                    "machine_id": None,
                    "result": "failed",
                    "failure_class": failure_class,
                },
            )
            continue

        starts.append(start)
        logger.info(
            "Worker start completed",
            extra={
                "process_group": process_group,
                "machine_id": start.machine_id,
                "result": start.status.value,
                "failure_class": None,
            },
        )

    return DemandMonitorResult(
        demand=demand,
        starts=tuple(starts),
        failures=tuple(failures),
    )


def worker_loop() -> None:
    """Poll durable queue demand forever while safely owning the Fly client."""
    machine_service: FlyMachineService | None = None
    failure_tracker = _FailureTracker()
    expiry_tracker = _TokenExpiryTracker()
    try:
        while True:
            cycle_started_at = monotonic()
            if not settings.worker_demand_monitor_enabled:
                failure_tracker.record(())
                _sleep_until_next_cycle(cycle_started_at)
                continue

            token = settings.fly_worker_control_token
            if token is None:
                logger.error(
                    "Fly worker control token is missing",
                    extra={
                        "process_group": None,
                        "machine_id": None,
                        "result": "missing_token",
                        "failure_class": "MissingFlyWorkerControlToken",
                    },
                )
                failure_tracker.record((_MISSING_TOKEN_FAILURE,))
                _sleep_until_next_cycle(cycle_started_at)
                continue

            expiry_tracker.record(
                settings.fly_worker_control_token_expires_at,
                today=_today(),
            )
            if machine_service is None:
                machine_service = FlyMachineService(
                    app_name=settings.fly_worker_control_app,
                    token=token,
                    api_base_url=settings.fly_machines_api_base_url,
                )

            result = execute_once(machine_service)
            failure_tracker.record(result.failures)
            _sleep_until_next_cycle(cycle_started_at)
    finally:
        if machine_service is not None:
            machine_service.close()


def _today() -> date:
    """Return the current UTC date through a monkeypatchable clock boundary."""
    return datetime.now(UTC).date()


def _sleep_until_next_cycle(cycle_started_at: float) -> None:
    """Maintain start-to-start cadence while yielding briefly after an overrun."""
    elapsed_seconds = monotonic() - cycle_started_at
    remaining_seconds = settings.worker_demand_poll_seconds - elapsed_seconds
    sleep(max(remaining_seconds, _MIN_CYCLE_SLEEP_SECONDS))
