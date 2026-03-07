"""Contract tests for the capability resolver service."""

from importlib import import_module

import pytest


def _resolver_service():
    try:
        module = import_module("api.services.capabilities.resolver")
    except ModuleNotFoundError as exc:
        pytest.fail(
            "Capability resolver service module missing: "
            "api.services.capabilities.resolver"
        )
    service = getattr(module, "CapabilityResolverService", None)
    if service is None:
        pytest.fail("CapabilityResolverService class missing from resolver module")
    return service


def _runtime_capability(
    skill_id: str,
    *,
    availability_status: str = "ready",
    availability_reason: str | None = None,
    availability_remediation: dict[str, str] | None = None,
) -> dict[str, object]:
    return {
        "skill_id": skill_id,
        "enabled": True,
        "availability_status": availability_status,
        "availability_reason": availability_reason,
        "availability_remediation": availability_remediation,
        "required_toolsets": [f"{skill_id}-tools"],
    }


def test_enabled_skills_define_capability_catalog_membership():
    result = _resolver_service().resolve_for_turn(
        user_message="Summarize my notes",
        enabled_skill_ids=["notes", "google-drive"],
        runtime_capabilities=[
            _runtime_capability("notes"),
            _runtime_capability(
                "google-drive",
                availability_status="needs_connection",
                availability_reason="missing_connection",
                availability_remediation={
                    "action": "connect",
                    "provider": "google-workspace",
                },
            ),
            _runtime_capability("files"),
        ],
    )

    assert result["catalog_skill_ids"] == ["notes", "google-drive"]
    assert "files" not in result["catalog_skill_ids"]


def test_blocked_skills_remain_selectable_for_remediation():
    result = _resolver_service().resolve_for_turn(
        user_message="Reconnect Google Drive so I can search it",
        enabled_skill_ids=["notes", "google-drive"],
        runtime_capabilities=[
            _runtime_capability("notes"),
            _runtime_capability(
                "google-drive",
                availability_status="needs_connection",
                availability_reason="missing_connection",
                availability_remediation={
                    "action": "connect",
                    "provider": "google-workspace",
                },
            ),
        ],
    )

    assert "google-drive" in result["selected_skill_ids"]
    assert result["blocked_skills"] == [
        {
            "skill_id": "google-drive",
            "availability_status": "needs_connection",
            "availability_reason": "missing_connection",
            "availability_remediation": {
                "action": "connect",
                "provider": "google-workspace",
            },
        }
    ]


def test_executable_skills_are_strict_subset_of_selected_skills():
    result = _resolver_service().resolve_for_turn(
        user_message="Use my notes and reconnect Google Drive",
        enabled_skill_ids=["notes", "google-drive"],
        runtime_capabilities=[
            _runtime_capability("notes"),
            _runtime_capability(
                "google-drive",
                availability_status="needs_connection",
                availability_reason="missing_connection",
                availability_remediation={
                    "action": "connect",
                    "provider": "google-workspace",
                },
            ),
        ],
    )

    assert set(result["executable_skill_ids"]).issubset(
        set(result["selected_skill_ids"])
    )
    assert result["selected_skill_ids"] == ["notes", "google-drive"]
    assert result["executable_skill_ids"] == ["notes"]
