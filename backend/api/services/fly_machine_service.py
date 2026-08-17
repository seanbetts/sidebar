"""Narrow, secret-safe control of existing Fly worker Machines."""

from __future__ import annotations

import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from enum import StrEnum
from typing import Literal, cast
from urllib.parse import quote

import httpx
from pydantic import SecretStr

WorkerProcessGroup = Literal["website", "ingestion"]

_CONTROLLED_PROCESS_GROUPS: tuple[WorkerProcessGroup, ...] = (
    "website",
    "ingestion",
)
_RETRY_DELAYS = (0.25, 0.5)
_TRANSIENT_STATUS_CODES = {408, 429}


class MachineStartStatus(StrEnum):
    """Successful outcomes for an existing Fly Machine start request."""

    STARTED = "started"
    ALREADY_ACTIVE = "already_active"


@dataclass(frozen=True, slots=True)
class MachineStartResult:
    """The outcome of ensuring one controlled Fly Machine is active."""

    process_group: WorkerProcessGroup
    machine_id: str
    status: MachineStartStatus


class FlyMachineError(RuntimeError):
    """Base error for the limited Fly Machines control boundary."""


class FlyMachineAuthenticationError(FlyMachineError):
    """Raised when Fly rejects the app-scoped control credential."""


class FlyMachineTopologyError(FlyMachineError):
    """Raised when the required existing worker Machine topology is invalid."""


class FlyMachineTransientError(FlyMachineError):
    """Raised for retryable Fly failures that the next monitor cycle may retry."""


@dataclass(frozen=True, slots=True)
class _ResolvedMachine:
    """A validated controlled Machine returned by Fly discovery."""

    machine_id: str
    state: str


class FlyMachineService:
    """Discover and start exactly one existing Fly worker Machine per process group."""

    def __init__(
        self,
        *,
        app_name: str,
        token: SecretStr,
        api_base_url: str = "https://api.machines.dev/v1",
        client: httpx.Client | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        """Initialize a client that can only list and start existing Machines."""
        self._app_name = app_name
        self._token = token
        self._client = client or httpx.Client(base_url=api_base_url, timeout=5.0)
        self._owns_client = client is None
        self._sleep = sleep
        self._machines: dict[WorkerProcessGroup, _ResolvedMachine] | None = None

    def ensure_started(self, process_group: WorkerProcessGroup) -> MachineStartResult:
        """Start a stopped controlled Machine or report that it is already active.

        Raises:
            FlyMachineAuthenticationError: Fly rejected the control credential.
            FlyMachineTopologyError: Required worker Machine topology is invalid.
            FlyMachineTransientError: A later monitor cycle should retry the request.
        """
        validated_group = self._validated_process_group(process_group)
        machine = self._resolved_machine(validated_group)

        if machine.state in {"started", "starting"}:
            self._machines = None
            return MachineStartResult(
                process_group=validated_group,
                machine_id=machine.machine_id,
                status=MachineStartStatus.ALREADY_ACTIVE,
            )
        if machine.state == "stopping":
            self._machines = None
            raise FlyMachineTransientError(
                "Fly Machine is stopping; retry on the next monitor cycle."
            )
        if machine.state not in {"stopped", "suspended"}:
            self._machines = None
            raise FlyMachineTransientError(
                "Fly Machine is not in a state that can be started safely."
            )

        return self._start_with_single_rediscovery(validated_group, machine)

    def close(self) -> None:
        """Close an HTTP client constructed and owned by this service."""
        if self._owns_client:
            self._client.close()

    def _start_with_single_rediscovery(
        self,
        process_group: WorkerProcessGroup,
        machine: _ResolvedMachine,
    ) -> MachineStartResult:
        """Start a Machine, rediscovering its ID no more than once after not found."""
        for refresh_attempted in (False, True):
            response = self._request(
                "POST",
                self._start_path(machine.machine_id),
            )
            if response.is_success:
                self._machines = None
                return MachineStartResult(
                    process_group=process_group,
                    machine_id=machine.machine_id,
                    status=MachineStartStatus.STARTED,
                )
            if response.status_code != 404:
                self._raise_for_unsuccessful_response(response)
            if refresh_attempted:
                self._machines = None
                raise FlyMachineTopologyError(
                    "Fly Machine was not found after one topology refresh."
                )

            self._machines = None
            machine = self._resolved_machine(process_group)
            if machine.state in {"started", "starting"}:
                self._machines = None
                return MachineStartResult(
                    process_group=process_group,
                    machine_id=machine.machine_id,
                    status=MachineStartStatus.ALREADY_ACTIVE,
                )
            if machine.state == "stopping":
                self._machines = None
                raise FlyMachineTransientError(
                    "Fly Machine is stopping; retry on the next monitor cycle."
                )
            if machine.state not in {"stopped", "suspended"}:
                self._machines = None
                raise FlyMachineTransientError(
                    "Fly Machine is not in a state that can be started safely."
                )

        raise AssertionError("The bounded Fly start loop must return or raise.")

    def _resolved_machine(self, process_group: WorkerProcessGroup) -> _ResolvedMachine:
        """Return a cached worker Machine or validate both groups through discovery."""
        if self._machines is None:
            self._machines = self._discover_machines()
        return self._machines[process_group]

    def _discover_machines(self) -> dict[WorkerProcessGroup, _ResolvedMachine]:
        """List Machines and require one existing Machine for each worker group."""
        response = self._request("GET", self._machines_path())
        if not response.is_success:
            self._raise_for_unsuccessful_response(response)

        try:
            payload = response.json()
        except ValueError as exc:
            raise FlyMachineTopologyError(
                "Fly Machine discovery returned invalid data."
            ) from exc
        if not isinstance(payload, list):
            raise FlyMachineTopologyError(
                "Fly Machine discovery returned invalid data."
            )

        matches: dict[WorkerProcessGroup, list[_ResolvedMachine]] = {
            group: [] for group in _CONTROLLED_PROCESS_GROUPS
        }
        for item in payload:
            if not isinstance(item, Mapping):
                continue
            process_group = _process_group(item)
            if process_group not in _CONTROLLED_PROCESS_GROUPS:
                continue
            machine_id = item.get("id")
            state = item.get("state")
            if not isinstance(machine_id, str) or not machine_id:
                raise FlyMachineTopologyError(
                    "Fly Machine discovery returned an invalid ID."
                )
            if not isinstance(state, str) or not state:
                raise FlyMachineTopologyError(
                    "Fly Machine discovery returned an invalid state."
                )
            controlled_group = cast(WorkerProcessGroup, process_group)
            matches[controlled_group].append(
                _ResolvedMachine(machine_id=machine_id, state=state)
            )

        resolved: dict[WorkerProcessGroup, _ResolvedMachine] = {}
        for process_group in _CONTROLLED_PROCESS_GROUPS:
            group_matches = matches[process_group]
            if len(group_matches) != 1:
                raise FlyMachineTopologyError(
                    "Fly Machine topology must contain exactly one "
                    f"{process_group} Machine."
                )
            resolved[process_group] = group_matches[0]
        return resolved

    def _request(self, method: str, path: str) -> httpx.Response:
        """Make one bounded Fly API request without exposing its authorization value."""
        for delay in (*_RETRY_DELAYS, None):
            try:
                response = self._client.request(
                    method,
                    path,
                    headers={
                        "Authorization": (f"Bearer {self._token.get_secret_value()}")
                    },
                )
            except httpx.RequestError as exc:
                if delay is None:
                    raise FlyMachineTransientError(
                        "Fly Machines API request failed after bounded retries."
                    ) from exc
                self._sleep(delay)
                continue

            if not self._is_transient_response(response):
                return response
            if delay is None:
                raise FlyMachineTransientError(
                    "Fly Machines API request failed after bounded retries."
                )
            self._sleep(delay)

        raise AssertionError("The bounded Fly request loop must return or raise.")

    def _raise_for_unsuccessful_response(self, response: httpx.Response) -> None:
        """Classify a final non-success Fly response without reading its body."""
        if response.status_code in {401, 403}:
            raise FlyMachineAuthenticationError(
                "Fly Machines API authentication failed."
            )
        raise FlyMachineError(
            f"Fly Machines API request failed with HTTP status {response.status_code}."
        )

    def _machines_path(self) -> str:
        """Return the only permitted Fly Machine discovery path."""
        return f"apps/{quote(self._app_name, safe='')}/machines"

    def _start_path(self, machine_id: str) -> str:
        """Return the only permitted Fly Machine mutation path."""
        return f"{self._machines_path()}/{quote(machine_id, safe='')}/start"

    @staticmethod
    def _is_transient_response(response: httpx.Response) -> bool:
        """Return whether Fly permits a bounded retry for this response."""
        return (
            response.status_code in _TRANSIENT_STATUS_CODES
            or response.status_code >= 500
        )

    @staticmethod
    def _validated_process_group(process_group: str) -> WorkerProcessGroup:
        """Reject process groups outside the two worker Machines it controls."""
        if process_group not in _CONTROLLED_PROCESS_GROUPS:
            raise FlyMachineTopologyError(
                "Fly Machine process group is not controlled."
            )
        return cast(WorkerProcessGroup, process_group)


def _process_group(machine: Mapping[str, object]) -> str | None:
    """Resolve Fly process-group metadata from each supported response location."""
    config = _mapping(machine.get("config"))
    metadata = _mapping(config.get("metadata"))
    env = _mapping(config.get("env"))
    process_group = (
        machine.get("process_group")
        or metadata.get("fly_process_group")
        or env.get("FLY_PROCESS_GROUP")
    )
    return process_group if isinstance(process_group, str) else None


def _mapping(value: object) -> Mapping[str, object]:
    """Return a mapping response fragment or an empty mapping for malformed Fly data."""
    if isinstance(value, Mapping):
        return cast(Mapping[str, object], value)
    return {}
