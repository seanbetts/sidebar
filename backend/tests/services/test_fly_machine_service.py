"""Tests for the narrow Fly Machine discovery and start client."""

import logging
from collections.abc import Callable

import httpx
import pytest
from pydantic import SecretStr

from api.services.fly_machine_service import (
    FlyMachineAuthenticationError,
    FlyMachineError,
    FlyMachineService,
    FlyMachineTopologyError,
    FlyMachineTransientError,
    MachineStartResult,
    MachineStartStatus,
)


def machine(machine_id: str, process_group: str, state: str) -> dict[str, object]:
    """Build a complete enough Fly Machine response for the service boundary."""
    return {
        "id": machine_id,
        "state": state,
        "config": {"metadata": {"fly_process_group": process_group}},
    }


def build_service(
    handler: Callable[[httpx.Request], httpx.Response],
    *,
    token: str = "test-token",
    sleeps: list[float] | None = None,
) -> FlyMachineService:
    """Build the service with a real synchronous client backed by a mock transport."""
    client = httpx.Client(
        base_url="https://api.machines.dev/v1",
        transport=httpx.MockTransport(handler),
    )
    return FlyMachineService(
        app_name="sidebar-api",
        token=SecretStr(token),
        client=client,
        sleep=(sleeps.append if sleeps is not None else lambda _seconds: None),
    )


def test_ensure_started_starts_the_single_stopped_process_machine() -> None:
    """A stopped website Machine is started through its precise Fly API endpoint."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "GET":
            return httpx.Response(
                200,
                json=[
                    machine("web-1", "website", "stopped"),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        return httpx.Response(202, json={"ok": True})

    service = build_service(handler)

    result = service.ensure_started("website")

    assert result == MachineStartResult(
        process_group="website",
        machine_id="web-1",
        status=MachineStartStatus.STARTED,
    )
    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
    ]
    assert all(
        request.headers["Authorization"] == "Bearer test-token" for request in requests
    )
    assert_only_discovery_or_start_requests(requests)


@pytest.mark.parametrize("state", ["started", "starting"])
def test_ensure_started_returns_already_active_for_active_machine(state: str) -> None:
    """An active or starting Machine must not receive a redundant start request."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json=[
                machine("web-1", "website", state),
                machine("ingest-1", "ingestion", "stopped"),
            ],
        )

    result = build_service(handler).ensure_started("website")

    assert result == MachineStartResult(
        process_group="website",
        machine_id="web-1",
        status=MachineStartStatus.ALREADY_ACTIVE,
    )
    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
    ]
    assert_only_discovery_or_start_requests(requests)


def test_active_machine_state_is_rediscovered_for_later_demand() -> None:
    """A cached active state cannot suppress a later start after the Machine stops."""
    requests: list[httpx.Request] = []
    discoveries = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal discoveries
        requests.append(request)
        if request.method == "GET":
            discoveries += 1
            state = "started" if discoveries == 1 else "stopped"
            return httpx.Response(
                200,
                json=[
                    machine("web-1", "website", state),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        return httpx.Response(202)

    service = build_service(handler)

    assert service.ensure_started("website").status is MachineStartStatus.ALREADY_ACTIVE
    assert service.ensure_started("website").status is MachineStartStatus.STARTED

    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
    ]
    assert_only_discovery_or_start_requests(requests)


def test_successful_start_is_rediscovered_before_later_demand() -> None:
    """A completed start cannot leave a stale stopped state for the next demand check."""
    requests: list[httpx.Request] = []
    discoveries = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal discoveries
        requests.append(request)
        if request.method == "GET":
            discoveries += 1
            state = "stopped" if discoveries == 1 else "started"
            return httpx.Response(
                200,
                json=[
                    machine("web-1", "website", state),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        return httpx.Response(202)

    service = build_service(handler)

    assert service.ensure_started("website").status is MachineStartStatus.STARTED
    assert service.ensure_started("website").status is MachineStartStatus.ALREADY_ACTIVE

    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
        ("GET", "/v1/apps/sidebar-api/machines"),
    ]
    assert_only_discovery_or_start_requests(requests)


@pytest.mark.parametrize("state", ["stopped", "suspended"])
@pytest.mark.parametrize("start_status", [200, 201, 202, 204])
def test_ensure_started_accepts_every_successful_start_response(
    state: str, start_status: int
) -> None:
    """Stopped and suspended Machines accept every Fly success response class."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "GET":
            return httpx.Response(
                200,
                json=[
                    machine("web-1", "website", state),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        return httpx.Response(start_status)

    result = build_service(handler).ensure_started("website")

    assert result == MachineStartResult(
        process_group="website",
        machine_id="web-1",
        status=MachineStartStatus.STARTED,
    )
    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
    ]
    assert_only_discovery_or_start_requests(requests)


def test_ensure_started_defers_a_stopping_machine_to_the_next_monitor_cycle() -> None:
    """A stopping Machine is transient rather than a start target or topology failure."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json=[
                machine("web-1", "website", "stopping"),
                machine("ingest-1", "ingestion", "stopped"),
            ],
        )

    with pytest.raises(FlyMachineTransientError):
        build_service(handler).ensure_started("website")

    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
    ]
    assert_only_discovery_or_start_requests(requests)


@pytest.mark.parametrize(
    "machines",
    [
        [machine("web-1", "website", "stopped")],
        [
            machine("web-1", "website", "stopped"),
            machine("web-2", "website", "stopped"),
            machine("ingest-1", "ingestion", "stopped"),
        ],
        [
            machine("web-1", "website", "stopped"),
            machine("ingest-1", "ingestion", "stopped"),
            machine("ingest-2", "ingestion", "stopped"),
        ],
    ],
)
def test_discovery_rejects_missing_or_duplicate_controlled_process_groups(
    machines: list[dict[str, object]],
) -> None:
    """Discovery refuses ambiguous or incomplete topology without starting anything."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=machines)

    with pytest.raises(FlyMachineTopologyError):
        build_service(handler).ensure_started("website")

    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
    ]
    assert_only_discovery_or_start_requests(requests)


@pytest.mark.parametrize(
    "website_machine",
    [
        {
            "id": "web-1",
            "state": "stopped",
            "process_group": "website",
            "config": {
                "metadata": {"fly_process_group": "ingestion"},
                "env": {"FLY_PROCESS_GROUP": "ingestion"},
            },
        },
        {
            "id": "web-1",
            "state": "stopped",
            "config": {
                "metadata": {"fly_process_group": "website"},
                "env": {"FLY_PROCESS_GROUP": "ingestion"},
            },
        },
    ],
)
def test_discovery_process_group_precedence_prefers_higher_priority_fields(
    website_machine: dict[str, object],
) -> None:
    """Top-level process group takes priority over metadata, then environment."""

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET":
            return httpx.Response(
                200,
                json=[website_machine, machine("ingest-1", "ingestion", "stopped")],
            )
        return httpx.Response(202)

    result = build_service(handler).ensure_started("website")

    assert result == MachineStartResult(
        process_group="website",
        machine_id="web-1",
        status=MachineStartStatus.STARTED,
    )


@pytest.mark.parametrize(
    "website_machine",
    [
        {"id": "web-1", "state": "stopped", "process_group": "website"},
        {
            "id": "web-1",
            "state": "stopped",
            "config": {"env": {"FLY_PROCESS_GROUP": "website"}},
        },
    ],
)
def test_discovery_uses_each_supported_process_group_location(
    website_machine: dict[str, object],
) -> None:
    """Fly's documented top-level, metadata, and environment group fields are supported."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "GET":
            return httpx.Response(
                200,
                json=[website_machine, machine("ingest-1", "ingestion", "stopped")],
            )
        return httpx.Response(202)

    result = build_service(handler).ensure_started("website")

    assert result.machine_id == "web-1"
    assert_only_discovery_or_start_requests(requests)


def test_start_404_refreshes_discovery_once_before_starting_the_replaced_machine() -> (
    None
):
    """A stale cached Machine ID is resolved once through fresh Fly discovery."""
    requests: list[httpx.Request] = []
    discoveries = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal discoveries
        requests.append(request)
        if request.method == "GET":
            discoveries += 1
            website_id = "web-old" if discoveries == 1 else "web-new"
            return httpx.Response(
                200,
                json=[
                    machine(website_id, "website", "stopped"),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        return httpx.Response(
            404 if request.url.path.endswith("web-old/start") else 202
        )

    result = build_service(handler).ensure_started("website")

    assert result == MachineStartResult(
        process_group="website",
        machine_id="web-new",
        status=MachineStartStatus.STARTED,
    )
    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-old/start"),
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-new/start"),
    ]
    assert_only_discovery_or_start_requests(requests)


def test_start_404_only_refreshes_discovery_once() -> None:
    """A second not-found response fails instead of looping Fly control requests."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "GET":
            return httpx.Response(
                200,
                json=[
                    machine("web-1", "website", "stopped"),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        return httpx.Response(404)

    with pytest.raises(FlyMachineTopologyError):
        build_service(handler).ensure_started("website")

    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
    ]
    assert_only_discovery_or_start_requests(requests)


@pytest.mark.parametrize("status_code", [401, 403])
def test_authentication_failures_are_not_retried(status_code: int) -> None:
    """Authentication denial returns a safe typed error after the first response."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(status_code, text="denied")

    with pytest.raises(FlyMachineAuthenticationError):
        build_service(handler).ensure_started("website")

    assert len(requests) == 1
    assert_only_discovery_or_start_requests(requests)


@pytest.mark.parametrize("status_code", [408, 429, 503])
def test_transient_discovery_responses_retry_at_most_three_times(
    status_code: int,
) -> None:
    """Transient Fly responses use exactly two injected backoff delays then stop."""
    requests: list[httpx.Request] = []
    sleeps: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(status_code)

    with pytest.raises(FlyMachineTransientError):
        build_service(handler, sleeps=sleeps).ensure_started("website")

    assert len(requests) == 3
    assert sleeps == [0.25, 0.5]
    assert_only_discovery_or_start_requests(requests)


def test_transient_start_response_retries_before_success() -> None:
    """A transient start response retries the exact existing-Machine start endpoint."""
    requests: list[httpx.Request] = []
    sleeps: list[float] = []
    start_attempts = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal start_attempts
        requests.append(request)
        if request.method == "GET":
            return httpx.Response(
                200,
                json=[
                    machine("web-1", "website", "stopped"),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        start_attempts += 1
        return httpx.Response(503 if start_attempts < 3 else 202)

    result = build_service(handler, sleeps=sleeps).ensure_started("website")

    assert result.status is MachineStartStatus.STARTED
    assert sleeps == [0.25, 0.5]
    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
    ]
    assert_only_discovery_or_start_requests(requests)


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, json={"not": "a list"}),
        httpx.Response(200, content=b"not-json"),
    ],
)
def test_discovery_rejects_malformed_machine_payloads(response: httpx.Response) -> None:
    """A malformed discovery payload is topology failure, never a partial start."""
    with pytest.raises(FlyMachineTopologyError):
        build_service(lambda _request: response).ensure_started("website")


@pytest.mark.parametrize(
    "invalid_machine",
    [
        {
            "id": "",
            "state": "stopped",
            "config": {"metadata": {"fly_process_group": "website"}},
        },
        {
            "id": "web-1",
            "state": "",
            "config": {"metadata": {"fly_process_group": "website"}},
        },
    ],
)
def test_discovery_rejects_controlled_machines_without_an_id_or_state(
    invalid_machine: dict[str, object],
) -> None:
    """Controlled Machines need a usable ID and state before any mutation is allowed."""

    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=[invalid_machine, machine("ingest-1", "ingestion", "stopped")],
        )

    with pytest.raises(FlyMachineTopologyError):
        build_service(handler).ensure_started("website")


def test_transport_failures_retry_at_most_three_times() -> None:
    """Network failures use the same bounded delays as transient Fly responses."""
    attempts = 0
    sleeps: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal attempts
        attempts += 1
        raise httpx.ConnectError("unavailable", request=request)

    with pytest.raises(FlyMachineTransientError):
        build_service(handler, sleeps=sleeps).ensure_started("website")

    assert attempts == 3
    assert sleeps == [0.25, 0.5]


def test_generic_final_client_error_is_typed_without_retrying() -> None:
    """A non-auth final client error does not become a retry loop or start request."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(400, text="bad request")

    with pytest.raises(FlyMachineError, match="HTTP status 400"):
        build_service(handler).ensure_started("website")

    assert len(requests) == 1
    assert_only_discovery_or_start_requests(requests)


def test_uncontrolled_process_group_is_rejected_without_a_fly_request() -> None:
    """The service refuses groups outside website and ingestion before discovery."""
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200)

    service = build_service(handler)

    with pytest.raises(FlyMachineTopologyError):
        service.ensure_started("app")  # type: ignore[arg-type]

    assert requests == []


@pytest.mark.parametrize(
    ("rediscovered_state", "expected_status", "error_type"),
    [
        ("started", MachineStartStatus.ALREADY_ACTIVE, None),
        ("starting", MachineStartStatus.ALREADY_ACTIVE, None),
        ("stopping", None, FlyMachineTransientError),
        ("created", None, FlyMachineTransientError),
    ],
)
def test_start_404_classifies_the_rediscovered_machine_state(
    rediscovered_state: str,
    expected_status: MachineStartStatus | None,
    error_type: type[Exception] | None,
) -> None:
    """A 404 refresh follows state rules before issuing another start request."""
    requests: list[httpx.Request] = []
    discoveries = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal discoveries
        requests.append(request)
        if request.method == "GET":
            discoveries += 1
            state = "stopped" if discoveries == 1 else rediscovered_state
            return httpx.Response(
                200,
                json=[
                    machine("web-1", "website", state),
                    machine("ingest-1", "ingestion", "stopped"),
                ],
            )
        return httpx.Response(404)

    service = build_service(handler)

    if error_type is None:
        assert service.ensure_started("website").status is expected_status
    else:
        with pytest.raises(error_type):
            service.ensure_started("website")

    assert [(request.method, request.url.path) for request in requests] == [
        ("GET", "/v1/apps/sidebar-api/machines"),
        ("POST", "/v1/apps/sidebar-api/machines/web-1/start"),
        ("GET", "/v1/apps/sidebar-api/machines"),
    ]
    assert_only_discovery_or_start_requests(requests)


def test_errors_and_logs_never_contain_the_token(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Authentication failures cannot disclose the Fly control token to logs or callers."""
    service = build_service(
        lambda _request: httpx.Response(401, text="denied"),
        token="do-not-log-this-token",
    )

    with (
        caplog.at_level(logging.DEBUG),
        pytest.raises(FlyMachineAuthenticationError) as raised,
    ):
        service.ensure_started("website")

    assert "do-not-log-this-token" not in str(raised.value)
    assert "do-not-log-this-token" not in caplog.text


def test_close_leaves_an_injected_client_open() -> None:
    """The service does not close an HTTP client whose lifecycle belongs to its caller."""
    client = httpx.Client(
        transport=httpx.MockTransport(lambda _request: httpx.Response(200))
    )
    service = FlyMachineService(
        app_name="sidebar-api",
        token=SecretStr("test-token"),
        client=client,
    )

    service.close()

    assert client.is_closed is False
    client.close()


def test_close_closes_a_client_constructed_by_the_service() -> None:
    """The service releases the HTTP client that it constructs for itself."""
    service = FlyMachineService(app_name="sidebar-api", token=SecretStr("test-token"))

    service.close()

    assert service._client.is_closed is True


def assert_only_discovery_or_start_requests(requests: list[httpx.Request]) -> None:
    """Ensure the client never makes an API request outside its narrow authority."""
    for request in requests:
        assert request.method in {"GET", "POST"}
        if request.method == "GET":
            assert request.url.path == "/v1/apps/sidebar-api/machines"
        else:
            assert request.url.path.startswith("/v1/apps/sidebar-api/machines/")
            assert request.url.path.endswith("/start")
