"""Tests for backend/scripts/fly_diagnostics.py."""

from __future__ import annotations

import json
from time import perf_counter

import pytest

import scripts.fly_diagnostics as fly_diagnostics
from scripts.fly_diagnostics import (
    _fetch_app,
    _fetch_logs,
    _parse_log_lines,
    build_fly_summary,
)


class _FakeResponse:
    def __init__(self, payload, *, text: str = "", status_code: int = 200) -> None:
        self._payload = payload
        self.text = text
        self.status_code = status_code

    def json(self):
        return self._payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise RuntimeError(f"status={self.status_code}")


class _FakeSession:
    def __init__(self, response: _FakeResponse) -> None:
        self.response = response
        self.calls: list[dict[str, object]] = []

    def get(self, url: str, **kwargs):
        self.calls.append({"url": url, **kwargs})
        return self.response


class _MainSession:
    """Network-free requests session used by main-command tests."""

    def __init__(self) -> None:
        self.headers: dict[str, str] = {}


def machine(
    machine_id: str,
    process_group: str,
    state: str,
    *,
    restart_count: int = 0,
) -> dict[str, object]:
    """Build a complete Fly Machine response fixture."""
    return {
        "id": machine_id,
        "state": state,
        "region": "lhr",
        "restart_count": restart_count,
        "updated_at": "2026-08-04T10:00:00Z",
        "config": {
            "guest": {"memory_mb": 512},
            "metadata": {"fly_process_group": process_group},
        },
    }


def healthy_topology() -> list[dict[str, object]]:
    """Build the expected four-Machine topology in a healthy steady state."""
    return [
        machine("api-1", "app", "stopped"),
        machine("control-1", "notification", "started"),
        machine("web-1", "website", "stopped"),
        machine("ingest-1", "ingestion", "suspended"),
    ]


_ESCAPED_CREDENTIAL_PROBES = [
    r"{\"Authorization\":\"REVIEW_ESCAPED_AUTH_COLON_SENTINEL\"}",
    r"{\\\"aUtHoRiZaTiOn\\\"=\\\"Bearer REVIEW_ESCAPED_AUTH_EQUALS_SENTINEL with spaces, semicolons; braces{}!\"}",
    r"{\"token\":\"REVIEW_ESCAPED_TOKEN_SENTINEL\"}",
    r"{\\\"api_key\\\":\\\"REVIEW_ESCAPED_API_KEY_SENTINEL\"}",
    r"{\"password\":\"REVIEW_ESCAPED_PASSWORD_SENTINEL\"}",
    r"{\\\"credential\\\":\\\"REVIEW_ESCAPED_CREDENTIAL_SENTINEL\"}",
]
_UNICODE_CREDENTIAL_PROBES = [
    r"{\u0022Authorization\u0022:\u0022REVIEW_UNICODE_ESCAPE_SENTINEL\u0022}",
    r"{\u0041uthorization\u0022:\u0022REVIEW_UNICODE_ESCAPE_SENTINEL\u0022}",
    r"Authorization\u003dREVIEW_UNICODE_ESCAPE_SENTINEL",
    r"Authorization\u003aREVIEW_UNICODE_ESCAPE_SENTINEL",
    r"\u0042\u0065arer\u0020REVIEW_UNICODE_BARE_BEARER_SENTINEL",
    r"{\\u0041uThOrIzAtIoN\\u003D\\u0022\u0042earer REVIEW_UNICODE_BEARER_SENTINEL, semi; braces{}!\\u0022}",
    r"{\U0074\u006f\u006b\u0065\u006e\u003a\u0022REVIEW_UNICODE_TOKEN_SENTINEL\u0022}",
    r"{\\u0061pi\u005fkey\\u003d\\u0022REVIEW_UNICODE_API_KEY_SENTINEL\\u0022}",
    r"{\u0070assword\u003a\u0022REVIEW_UNICODE_PASSWORD_SENTINEL\u0022,\u0063redential\u003d\u0022REVIEW_UNICODE_CREDENTIAL_SENTINEL\u0022}",
]
_NESTED_UNICODE_CREDENTIAL_PROBES = [
    r"{\\u005cu0022Authorization\\u005cu0022:\\u005cu0022REVIEW_ROUND3_SENTINEL\\u005cu0022}",
    r"Authorization\\u005cu003dREVIEW_ROUND3_SENTINEL",
    (
        r"{\\u005cu005cu0022to\u006ben\\u005cu005cu0022"
        r"\\u005cu005cu003a\\u005cu005cu0022"
        r"REVIEW_NESTED_TOKEN_SENTINEL with spaces, semicolons; braces{}!"
        r"\\u005cu005cu0022}"
    ),
    (
        r"{\\U005cU005cU005cU0022a\U0070i\u005Fkey\\U005cU005cU005cU0022"
        r"\u0020\\U005cU005cU005cU003D\u0009"
        r"\\U005cU005cU005cU0022REVIEW_NESTED_API_KEY_SENTINEL!? ,;{}"
        r"\\U005cU005cU005cU0022}"
    ),
    (
        r"{\\u005cu005cu005cu005cu0022pa\u0073sword"
        r"\\u005cu005cu005cu005cu0022:"
        r"\\u005cu005cu005cu005cu0022REVIEW_NESTED_PASSWORD_SENTINEL"
        r" with whitespace, punctuation;{}!\\u005cu005cu005cu005cu0022}"
    ),
    (
        r"{\\u005cu005cu005cu005cu005cu005cu0022cre\u0064ential"
        r"\\u005cu005cu005cu005cu005cu005cu0022"
        r"\\u005cu005cu005cu005cu005cu005cu003d"
        r"\\u005cu005cu005cu005cu005cu005cu0022"
        r"REVIEW_NESTED_CREDENTIAL_SENTINEL\\u005cu005cu005cu005cu005cu005cu0022}"
    ),
    (
        r"{\\u005cu005cu0022Au\u0074horization\\u005cu005cu0022"
        r"\u003a\\u005cu005cu0022Bearer\u0020"
        r"REVIEW_NESTED_AUTH_BEARER_SENTINEL with spaces, semi; braces{}!"
        r"\\u005cu005cu0022}"
    ),
]
_ALL_UNICODE_CREDENTIAL_PROBES = [
    *_UNICODE_CREDENTIAL_PROBES,
    *_NESTED_UNICODE_CREDENTIAL_PROBES,
]
_LINEAR_SANITIZER_BUDGET_SECONDS = 1.5


def test_summary_accepts_stopped_demand_workers_as_healthy() -> None:
    """Stopped demand workers and API are valid demand-driven steady state."""
    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=healthy_topology(),
        logs=[],
    )

    assert result["status"] == "ok"
    assert result["warnings"] == []
    assert result["data"]["process_groups"]["website"] == [
        {
            "id": "web-1",
            "process_group": "website",
            "state": "stopped",
            "region": "lhr",
            "memory_mb": 512,
            "restart_count": 0,
            "updated_at": "2026-08-04T10:00:00Z",
        }
    ]


@pytest.mark.parametrize(
    "machines",
    [
        healthy_topology()[:-1],
        [*healthy_topology(), machine("web-2", "website", "stopped")],
    ],
)
def test_summary_warns_when_process_group_topology_is_not_exactly_one(
    machines: list[dict[str, object]],
) -> None:
    """A missing or duplicate expected process group requires deployment repair."""
    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[],
    )

    assert result["status"] == "warn"
    assert result["warnings"] == ["machine topology is invalid"]


def test_summary_warns_when_notification_control_is_stopped() -> None:
    """The notification control Machine must continuously remain active."""
    machines = healthy_topology()
    machines[1]["state"] = "stopped"

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[],
    )

    assert result["status"] == "warn"
    assert result["warnings"] == ["notification control machine is not active"]


def test_summary_warns_when_demand_machine_state_is_not_supported() -> None:
    """Demand Machines outside their lifecycle state model indicate invalid topology."""
    machines = healthy_topology()
    machines[2]["state"] = "failed"

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[],
    )

    assert result["status"] == "warn"
    assert result["warnings"] == ["machine topology is invalid"]


def test_summary_warns_when_machine_has_recent_restarts() -> None:
    """A restart in a valid worker topology should elevate the Fly summary."""
    machines = healthy_topology()
    machines[2]["restart_count"] = 3

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[],
    )

    assert result["status"] == "warn"
    assert result["warnings"] == ["machines have recent restarts"]


def test_summary_uses_stable_warning_precedence() -> None:
    """Topology, control, restarts, then logs provides deterministic triage order."""
    machines = healthy_topology()[:-1]
    machines[1]["state"] = "stopped"
    machines[2]["restart_count"] = 1

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[{"level": "error", "message": "boom"}],
    )

    assert result["status"] == "warn"
    assert result["warnings"] == [
        "machine topology is invalid",
        "notification control machine is not active",
        "machines have recent restarts",
        "recent error logs detected",
    ]


def test_summary_keeps_app_status_as_data_not_a_topology_warning() -> None:
    """The app control-plane status remains available without a duplicate warning type."""
    result = build_fly_summary(
        app={"name": "sidebar", "status": "maintenance"},
        machines=healthy_topology(),
        logs=[],
    )

    assert result["status"] == "ok"
    assert result["data"]["app_status"] == "maintenance"
    assert result["warnings"] == []


def test_summary_uses_fly_machine_service_process_group_precedence() -> None:
    """Top-level, metadata, then environment process groups classify Machines."""
    machines = healthy_topology()
    machines[0]["process_group"] = "app"
    machines[0]["config"] = {
        "metadata": {"fly_process_group": "website"},
        "env": {"FLY_PROCESS_GROUP": "ingestion"},
    }
    machines[1]["config"] = {
        "metadata": {"fly_process_group": "notification"},
        "env": {"FLY_PROCESS_GROUP": "ingestion"},
    }
    machines[2]["config"] = {"env": {"FLY_PROCESS_GROUP": "website"}}

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[],
    )

    assert result["status"] == "ok"
    assert [row["id"] for row in result["data"]["process_groups"]["app"]] == ["api-1"]
    assert [row["id"] for row in result["data"]["process_groups"]["notification"]] == [
        "control-1"
    ]
    assert [row["id"] for row in result["data"]["process_groups"]["website"]] == [
        "web-1"
    ]


def test_summary_warns_for_unknown_or_malformed_process_group_payloads() -> None:
    """Unrecognised or malformed Machine metadata must not appear as healthy topology."""
    machines = healthy_topology()
    machines[3]["config"] = {"metadata": {"fly_process_group": "unknown"}}
    machines.append({"id": "broken-1", "state": "started", "config": []})

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[],
    )

    assert result["status"] == "warn"
    assert result["warnings"] == ["machine topology is invalid"]
    assert result["data"]["process_groups"]["ingestion"] == []
    assert result["data"]["process_groups"]["unrecognized"] == [
        {
            "id": "ingest-1",
            "process_group": "unknown",
            "state": "suspended",
            "region": "lhr",
            "memory_mb": None,
            "restart_count": 0,
            "updated_at": "2026-08-04T10:00:00Z",
        },
        {
            "id": "broken-1",
            "process_group": None,
            "state": "started",
            "region": None,
            "memory_mb": None,
            "restart_count": 0,
            "updated_at": None,
        },
    ]
    assert sum(len(rows) for rows in result["data"]["process_groups"].values()) == 5


def test_summary_redacts_machine_and_log_secrets() -> None:
    """Summary data must not retain credentials from Fly payloads or error logs."""
    machines = healthy_topology()
    machines[0]["config"] = {
        "guest": {"memory_mb": 512},
        "metadata": {"fly_process_group": "app", "api_token": "machine-secret"},
        "env": {"FLY_PROCESS_GROUP": "app", "SECRET_KEY": "also-secret"},
        "authorization": "Bearer machine-authorization",
    }
    logs = [
        {
            "level": "error",
            "message": "Authorization: Bearer log-secret token=also-log-secret",
            "token": "payload-token",
        }
    ]

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=logs,
    )

    rendered = json.dumps(result)
    assert result["status"] == "warn"
    assert "machine-secret" not in rendered
    assert "machine-authorization" not in rendered
    assert "log-secret" not in rendered
    assert "also-log-secret" not in rendered
    assert "payload-token" not in rendered
    assert "authorization" not in rendered.lower()


@pytest.mark.parametrize(
    "message",
    [
        "request failed Authorization: Bearer REVIEW_LEAK_SENTINEL",
        "request failed Authorization=REVIEW_LEAK_SENTINEL",
        '{"Authorization":"REVIEW_LEAK_SENTINEL"}',
        "AuThOrIzAtIoN = 'REVIEW_LEAK_SENTINEL'; retrying",
        'context={"aUtHoRiZaTiOn" : "Bearer REVIEW_LEAK_SENTINEL"}',
        "API_KEY=REVIEW_LEAK_SENTINEL, password:'REVIEW_LEAK_SENTINEL'",
        'credential-shaped "REVIEW_LEAK_SENTINEL_123456789" response',
        'Authorization="REVIEW_LEAK_PREFIX,REVIEW_LEAK_SUFFIX"; retrying',
    ],
)
def test_log_rows_redact_credential_forms_and_punctuation(message: str) -> None:
    """Every supported credential representation is absent from rendered logs."""
    rows = _parse_log_lines(json.dumps({"level": "error", "message": message}))

    rendered = json.dumps(rows)
    assert "REVIEW_LEAK_SENTINEL" not in rendered
    assert "REVIEW_LEAK_PREFIX" not in rendered
    assert "REVIEW_LEAK_SUFFIX" not in rendered
    assert "authorization" not in rendered.lower()


def test_log_rows_redact_bare_bearer_credentials() -> None:
    """Credentials remain absent even when a log omits the Authorization key."""
    rows = _parse_log_lines('{"level":"error","message":"Bearer bare-secret failed"}')

    assert rows == [{"level": "error", "message": "[REDACTED] failed"}]


@pytest.mark.parametrize("message", _ESCAPED_CREDENTIAL_PROBES)
def test_log_rows_redact_backslash_escaped_credential_assignments(
    message: str,
) -> None:
    """Escaped JSON layers cannot bypass the shared diagnostic sanitizer."""
    rows = _parse_log_lines(json.dumps({"level": "error", "message": message}))

    rendered = json.dumps(rows)
    assert "REVIEW_ESCAPED_" not in rendered
    assert "[REDACTED]" in rendered


@pytest.mark.parametrize("escaped_credential", _ESCAPED_CREDENTIAL_PROBES)
def test_backslash_escaped_credentials_are_rejected_from_projected_text_fields(
    escaped_credential: str,
) -> None:
    """Every projected scalar text field rejects the same escaped credential."""
    machine_rows = []
    for field in ("id", "process_group", "state", "region", "updated_at"):
        candidate = machine("web-1", "website", "stopped")
        if field == "process_group":
            candidate["config"]["metadata"]["fly_process_group"] = escaped_credential
        else:
            candidate[field] = escaped_credential
        machine_rows.append(fly_diagnostics._build_machine_row(candidate))

    projected = {
        "machine_rows": machine_rows,
        "app": fly_diagnostics._build_app_row(
            {"name": escaped_credential, "status": escaped_credential}
        ),
        "summary": build_fly_summary(
            app={"name": "sidebar", "status": escaped_credential},
            machines=healthy_topology(),
            logs=[],
        ),
        "deploys": fly_diagnostics._build_deploy_rows(
            [
                {
                    "id": escaped_credential,
                    "state": escaped_credential,
                    "updated_at": escaped_credential,
                    "config": {"image": escaped_credential},
                }
            ]
        ),
        "logs": fly_diagnostics._build_log_rows(
            [{"level": escaped_credential, "message": escaped_credential}]
        ),
    }

    rendered = json.dumps(projected)
    assert "REVIEW_ESCAPED_" not in rendered
    assert "[REDACTED]" in rendered


@pytest.mark.parametrize("message", _ALL_UNICODE_CREDENTIAL_PROBES)
def test_log_rows_redact_json_unicode_escaped_credential_assignments(
    message: str,
) -> None:
    """JSON Unicode escapes cannot conceal a credential assignment in logs."""
    rows = _parse_log_lines(json.dumps({"level": "error", "message": message}))

    rendered = json.dumps(rows)
    assert "REVIEW_" not in rendered
    assert "[REDACTED]" in rendered


@pytest.mark.parametrize("escaped_credential", _ALL_UNICODE_CREDENTIAL_PROBES)
def test_json_unicode_escaped_credentials_are_rejected_from_projected_text_fields(
    escaped_credential: str,
) -> None:
    """All scalar text projections reject Unicode-escaped credentials equally."""
    machine_rows = []
    for field in ("id", "process_group", "state", "region", "updated_at"):
        candidate = machine("web-1", "website", "stopped")
        if field == "process_group":
            candidate["config"]["metadata"]["fly_process_group"] = escaped_credential
        else:
            candidate[field] = escaped_credential
        machine_rows.append(fly_diagnostics._build_machine_row(candidate))

    projected = {
        "machine_rows": machine_rows,
        "app": fly_diagnostics._build_app_row(
            {"name": escaped_credential, "status": escaped_credential}
        ),
        "summary": build_fly_summary(
            app={"name": "sidebar", "status": escaped_credential},
            machines=healthy_topology(),
            logs=[],
        ),
        "deploys": fly_diagnostics._build_deploy_rows(
            [
                {
                    "id": escaped_credential,
                    "state": escaped_credential,
                    "updated_at": escaped_credential,
                    "config": {"image": escaped_credential},
                }
            ]
        ),
        "logs": fly_diagnostics._build_log_rows(
            [{"level": escaped_credential, "message": escaped_credential}]
        ),
    }

    rendered = json.dumps(projected)
    assert "REVIEW_" not in rendered
    assert "[REDACTED]" in rendered


@pytest.mark.parametrize(
    "benign",
    [
        r"healthy response \u2603",
        r"healthy nested response \\u005cu2603",
        r"healthy incomplete response \\u005cu00ZZ",
        r"healthy encoded slash \\u005c",
    ],
)
def test_sanitizer_preserves_irrelevant_unicode_escapes(benign: str) -> None:
    """Irrelevant Unicode escapes are never broadly decoded into diagnostics."""
    assert fly_diagnostics._sanitize_diagnostic_text(benign) == benign


def test_sanitizer_converges_for_deep_nested_unicode_credentials() -> None:
    """A long escape chain terminates and cannot outlast normalization."""
    depth = 256
    nested_quote = r"\\u005c" + ("u005c" * (depth - 1)) + "u0022"
    message = (
        f"prefix {{ {nested_quote}Authorization{nested_quote}:"
        f"{nested_quote}REVIEW_DEEP_UNICODE_SENTINEL{nested_quote} }} suffix"
    )

    assert fly_diagnostics._sanitize_diagnostic_text(message) == (
        "prefix { [REDACTED] } suffix"
    )


@pytest.mark.parametrize(
    ("initial_backslashes", "continuation_backslashes"),
    [(1, 1), (2, 3), (4, 2)],
)
def test_sanitizer_collapses_unicode_chains_across_literal_backslashes(
    initial_backslashes: int,
    continuation_backslashes: int,
) -> None:
    """Literal backslashes inside a valid chain cannot conceal its separator."""
    separator = (
        ("\\" * initial_backslashes)
        + "u005c"
        + ("\\" * continuation_backslashes)
        + "u003d"
    )
    message = f"Authorization{separator}REVIEW_CHAIN_SENTINEL"

    assert fly_diagnostics._sanitize_diagnostic_text(message) == "[REDACTED]"


def test_sanitizer_processes_deep_nested_credentials_within_linear_budget() -> None:
    """Deep valid nesting must not trigger repeated whole-string rescans."""
    depth = 2048
    nested_quote = r"\\u005c" + ("u005c" * (depth - 1)) + "u0022"
    message = (
        f"prefix {{ {nested_quote}Authorization{nested_quote}:"
        f"{nested_quote}REVIEW_LINEAR_SENTINEL{nested_quote} }} suffix"
    )

    started = perf_counter()
    sanitized = fly_diagnostics._sanitize_diagnostic_text(message)
    elapsed = perf_counter() - started

    assert sanitized == "prefix { [REDACTED] } suffix"
    assert elapsed < _LINEAR_SANITIZER_BUDGET_SECONDS


def test_sanitizer_preserves_large_benign_chain_within_linear_budget() -> None:
    """A deep chain ending outside the whitelist stays byte-for-byte unchanged."""
    message = "healthy " + (r"\u005c" * 4096) + r"\u2603"

    started = perf_counter()
    sanitized = fly_diagnostics._sanitize_diagnostic_text(message)
    elapsed = perf_counter() - started

    assert sanitized == message
    assert elapsed < _LINEAR_SANITIZER_BUDGET_SECONDS


@pytest.mark.parametrize(
    "suffix", [r"\u00", r"\u00ZZ"], ids=["incomplete", "malformed"]
)
def test_sanitizer_preserves_large_invalid_chains_within_linear_budget(
    suffix: str,
) -> None:
    """Incomplete and malformed chain tails terminate without suffix rescans."""
    message = "healthy " + (r"\u005c" * 4096) + suffix

    started = perf_counter()
    sanitized = fly_diagnostics._sanitize_diagnostic_text(message)
    elapsed = perf_counter() - started

    assert sanitized == message
    assert elapsed < _LINEAR_SANITIZER_BUDGET_SECONDS


@pytest.mark.parametrize("suffix", ["u00", "u00ZZ"], ids=["incomplete", "malformed"])
def test_sanitizer_preserves_large_invalid_backslash_runs_within_linear_budget(
    suffix: str,
) -> None:
    """Malformed data after a long slash run must not trigger regex rescans."""
    message = "healthy " + ("\\" * 32768) + suffix

    started = perf_counter()
    sanitized = fly_diagnostics._sanitize_diagnostic_text(message)
    elapsed = perf_counter() - started

    assert sanitized == message
    assert elapsed < _LINEAR_SANITIZER_BUDGET_SECONDS


@pytest.mark.parametrize(
    ("field", "value", "expected"),
    [
        ("id", {"token": "REVIEW_ROW_LEAK"}, None),
        ("process_group", {"token": "REVIEW_ROW_LEAK"}, None),
        ("state", ["REVIEW_ROW_LEAK"], None),
        ("region", "Authorization=REVIEW_ROW_LEAK", None),
        ("memory_mb", {"api_key": "REVIEW_ROW_LEAK"}, None),
        ("restart_count", ["REVIEW_ROW_LEAK"], 0),
        ("updated_at", {"secret": "REVIEW_ROW_LEAK"}, None),
    ],
)
def test_summary_projects_untrusted_machine_fields_to_safe_scalar_values(
    field: str,
    value: object,
    expected: object,
) -> None:
    """Nested and credential-shaped values never survive approved row projection."""
    machines = healthy_topology()
    website = machines[2]
    if field == "memory_mb":
        website["config"]["guest"]["memory_mb"] = value
    elif field == "process_group":
        website["process_group"] = value
    else:
        website[field] = value

    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=machines,
        logs=[],
    )

    row = result["data"]["process_groups"]["unrecognized"][0]
    rendered = json.dumps(result)
    assert result["status"] == "warn"
    assert row[field] == expected
    assert "REVIEW_ROW_LEAK" not in rendered
    assert all(value is None or isinstance(value, (str, int)) for value in row.values())


@pytest.mark.parametrize(
    "args",
    [
        ["summary", "--json"],
        ["status", "--json"],
        ["deploys", "--json"],
        ["machines", "--json"],
        ["logs", "--json"],
    ],
)
def test_main_projects_all_diagnostic_command_payloads(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    args: list[str],
) -> None:
    """Each local command branch emits a safe JSON envelope without raw payloads."""
    _configure_main(monkeypatch)
    machines = healthy_topology()
    machines[2]["region"] = {"token": "REVIEW_MAIN_LEAK"}
    machines[2]["config"]["image"] = {"token": "REVIEW_MAIN_LEAK"}
    monkeypatch.setattr(
        fly_diagnostics,
        "_fetch_app",
        lambda *_args, **_kwargs: {
            "name": {"token": "REVIEW_MAIN_LEAK"},
            "status": "Authorization=REVIEW_MAIN_LEAK",
        },
    )
    monkeypatch.setattr(
        fly_diagnostics,
        "_fetch_machines",
        lambda *_args, **_kwargs: machines,
    )
    monkeypatch.setattr(
        fly_diagnostics,
        "_fetch_logs",
        lambda *_args, **_kwargs: [
            {
                "level": "error",
                "message": "Authorization=REVIEW_MAIN_LEAK",
                "token": "REVIEW_MAIN_LEAK",
            }
        ],
    )

    assert fly_diagnostics.main(args) == 0

    payload = json.loads(capsys.readouterr().out)
    assert payload["command"] == args[0]
    assert "REVIEW_MAIN_LEAK" not in json.dumps(payload)


def test_main_reports_missing_configuration_without_making_requests(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The stable config envelope remains available before any Fly request exists."""
    monkeypatch.setattr(fly_diagnostics, "load_local_env", lambda: None)
    monkeypatch.delenv("OPS_FLY_API_TOKEN", raising=False)
    monkeypatch.delenv("OPS_FLY_APP", raising=False)

    assert fly_diagnostics.main(["summary", "--json"]) == 2

    payload = json.loads(capsys.readouterr().out)
    assert payload["errors"] == [
        "Missing environment variable: OPS_FLY_API_TOKEN",
        "Missing environment variable: OPS_FLY_APP",
    ]


@pytest.mark.parametrize("args", [["status", "--json"], ["status"]])
def test_main_never_emits_raw_exception_text(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    args: list[str],
) -> None:
    """JSON and text errors keep a raised credential out of the command envelope."""
    _configure_main(monkeypatch)
    monkeypatch.setattr(
        fly_diagnostics,
        "_fetch_app",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            RuntimeError("Authorization=REVIEW_ERROR_LEAK_SENTINEL")
        ),
    )

    assert fly_diagnostics.main(args) == 1

    rendered = capsys.readouterr().out
    assert "REVIEW_ERROR_LEAK_SENTINEL" not in rendered
    assert "Authorization" not in rendered
    assert "Fly diagnostics request failed." in rendered


def _configure_main(monkeypatch: pytest.MonkeyPatch) -> None:
    """Install local-only main dependencies and stable test credentials."""
    monkeypatch.setattr(fly_diagnostics, "load_local_env", lambda: None)
    monkeypatch.setattr(fly_diagnostics.requests, "Session", _MainSession)
    monkeypatch.setenv("OPS_FLY_API_TOKEN", "test-fly-token")
    monkeypatch.setenv("OPS_FLY_APP", "sidebar")


def test_fetch_app_uses_bearer_authorization_header() -> None:
    """Machines API requests should keep using bearer auth."""
    session = _FakeSession(_FakeResponse({"status": "deployed"}))

    _fetch_app(session, "sidebar", token="fly-token")

    assert session.calls == [
        {
            "url": "https://api.machines.dev/v1/apps/sidebar",
            "headers": {"Authorization": "Bearer fly-token"},
            "timeout": 15,
        }
    ]


def test_fetch_logs_uses_raw_authorization_header() -> None:
    """Fly logs endpoint requires the raw FlyV1 token, not bearer auth."""
    session = _FakeSession(_FakeResponse({}, text='{"level":"info","message":"ok"}'))

    _fetch_logs(session, "sidebar", region="lhr", token="fly-token")

    assert session.calls == [
        {
            "url": "https://api.fly.io/api/v1/apps/sidebar/logs",
            "headers": {"Authorization": "fly-token"},
            "params": {"region": "lhr"},
            "timeout": 15,
        }
    ]
