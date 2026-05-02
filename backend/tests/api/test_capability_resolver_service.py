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
    name: str | None = None,
    description: str | None = None,
    tags: list[str] | None = None,
    triggers: list[str] | None = None,
    availability_status: str = "ready",
    availability_reason: str | None = None,
    availability_remediation: dict[str, str] | None = None,
) -> dict[str, object]:
    return {
        "skill_id": skill_id,
        "name": name or skill_id.replace("-", " ").title(),
        "description": description or "",
        "enabled": True,
        "availability_status": availability_status,
        "availability_reason": availability_reason,
        "availability_remediation": availability_remediation,
        "tags": tags or [],
        "triggers": triggers or [],
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


def test_resolver_prefers_open_context_fast_path_for_note_requests():
    result = _resolver_service().resolve_for_turn(
        user_message="Summarize this note",
        enabled_skill_ids=["notes", "files"],
        open_context={"note": {"id": "note-1", "title": "Draft"}},
        runtime_capabilities=[
            _runtime_capability(
                "notes",
                tags=["notes"],
                triggers=["note", "summarize"],
            ),
            _runtime_capability(
                "files",
                tags=["files"],
                triggers=["file", "folder"],
            ),
        ],
    )

    assert result["selected_skill_ids"] == ["notes"]
    assert result["executable_skill_ids"] == ["notes"]


def test_resolver_prefers_open_context_fast_path_for_website_requests():
    result = _resolver_service().resolve_for_turn(
        user_message="Summarize this",
        enabled_skill_ids=["web-save", "files"],
        open_context={"website": {"id": "web-1", "title": "Spec"}},
        runtime_capabilities=[
            _runtime_capability(
                "web-save",
                name="Archive",
                description="",
                tags=[],
                triggers=[],
            ),
            _runtime_capability(
                "files",
                name="Workspace",
                description="",
                tags=[],
                triggers=[],
            ),
        ],
    )

    assert result["selected_skill_ids"] == ["web-save"]
    assert result["executable_skill_ids"] == ["web-save"]


def test_resolver_falls_back_to_search_when_fast_paths_are_weak():
    result = _resolver_service().resolve_for_turn(
        user_message="Find the config file in my project",
        enabled_skill_ids=["notes", "files"],
        runtime_capabilities=[
            _runtime_capability(
                "notes",
                description="Summarize and organize notes.",
                tags=["notes"],
                triggers=["note", "journal"],
            ),
            _runtime_capability(
                "files",
                description="Search and inspect files in the workspace.",
                tags=["files", "workspace"],
                triggers=["file", "project", "config"],
            ),
        ],
    )

    assert result["selected_skill_ids"] == ["files"]
    assert result["executable_skill_ids"] == ["files"]
    assert "tool_definitions" not in result


def test_resolver_selects_prompt_preview_for_system_prompt_requests():
    result = _resolver_service().resolve_for_turn(
        user_message="What instructions are you running under?",
        enabled_skill_ids=["notes", "prompt-preview", "files"],
        runtime_capabilities=[
            _runtime_capability(
                "notes",
                description="Search and summarize notes.",
                tags=["notes"],
                triggers=["note", "summarize"],
            ),
            _runtime_capability(
                "prompt-preview",
                name="Prompt Preview",
                description="Generate the current system prompt output for preview.",
            ),
            _runtime_capability(
                "files",
                description="Search and inspect files in the workspace.",
                tags=["files", "workspace"],
                triggers=["file", "project", "config"],
            ),
        ],
    )

    assert result["selected_skill_ids"] == ["prompt-preview"]
    assert result["executable_skill_ids"] == ["prompt-preview"]


def test_resolver_adds_onboarding_coach_for_incomplete_onboarding():
    result = _resolver_service().resolve_for_turn(
        user_message="Help me finish setup",
        enabled_skill_ids=["onboarding-coach", "notes"],
        runtime_capabilities=[
            _runtime_capability(
                "onboarding-coach",
                description="Guide incomplete users through setup recovery.",
                tags=["onboarding", "setup"],
                triggers=["finish setup", "connect key"],
            ),
            _runtime_capability(
                "notes",
                description="Search and summarize notes.",
                tags=["notes"],
                triggers=["note", "summarize"],
            ),
        ],
        onboarding_state={
            "status": "dismissed",
            "current_onboarding_step": "provider_recovery",
            "is_onboarding_complete": False,
            "provider_ready": False,
        },
    )

    assert result["selected_skill_ids"] == ["onboarding-coach"]
    assert result["executable_skill_ids"] == ["onboarding-coach"]


def test_resolver_augments_feature_discovery_with_onboarding_coach():
    user_message = (
        "Help me get started with Notes in sideBar. "
        "Give me a short guided intro and one simple first win."
    )
    enabled_skill_ids = ["onboarding-coach", "notes", "files"]
    runtime_capabilities = [
        _runtime_capability(
            "onboarding-coach",
            description="Guide incomplete users through setup recovery.",
            tags=["onboarding", "setup"],
            triggers=["finish setup", "connect key"],
        ),
        _runtime_capability(
            "notes",
            description="Search and summarize notes.",
            tags=["notes"],
            triggers=["note", "notes"],
        ),
        _runtime_capability(
            "files",
            description="Search and inspect files in the workspace.",
            tags=["files", "workspace"],
            triggers=["file", "project", "config"],
        ),
    ]

    baseline = _resolver_service().resolve_for_turn(
        user_message=user_message,
        enabled_skill_ids=enabled_skill_ids,
        runtime_capabilities=runtime_capabilities,
        onboarding_state={
            "status": "completed",
            "current_onboarding_step": "completed",
            "is_onboarding_complete": True,
            "provider_ready": True,
        },
    )

    result = _resolver_service().resolve_for_turn(
        user_message=user_message,
        enabled_skill_ids=enabled_skill_ids,
        runtime_capabilities=runtime_capabilities,
        onboarding_state={
            "status": "dismissed",
            "current_onboarding_step": "feature_discovery",
            "is_onboarding_complete": False,
            "provider_ready": True,
        },
    )

    assert result["selected_skill_ids"] == [
        "onboarding-coach",
        *baseline["selected_skill_ids"],
    ]
    assert result["executable_skill_ids"] == [
        "onboarding-coach",
        *baseline["executable_skill_ids"],
    ]


def test_resolver_omits_onboarding_coach_for_completed_onboarding():
    result = _resolver_service().resolve_for_turn(
        user_message="Summarize my notes",
        enabled_skill_ids=["onboarding-coach", "notes"],
        runtime_capabilities=[
            _runtime_capability(
                "onboarding-coach",
                description="Guide incomplete users through setup recovery.",
                tags=["onboarding", "setup"],
                triggers=["finish setup", "connect key"],
            ),
            _runtime_capability(
                "notes",
                description="Search and summarize notes.",
                tags=["notes"],
                triggers=["note", "summarize"],
            ),
        ],
        onboarding_state={
            "status": "completed",
            "current_onboarding_step": "completed",
            "is_onboarding_complete": True,
            "provider_ready": True,
        },
    )

    assert result["selected_skill_ids"] == ["notes"]
    assert result["executable_skill_ids"] == ["notes"]
