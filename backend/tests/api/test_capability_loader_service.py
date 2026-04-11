"""Contract tests for the capability loader service."""

from importlib import import_module
import logging
from pathlib import Path

import pytest


def _loader_service():
    try:
        module = import_module("api.services.capabilities.loader")
    except ModuleNotFoundError:
        pytest.fail(
            "Capability loader service module missing: "
            "api.services.capabilities.loader"
        )

    service = getattr(module, "CapabilityLoaderService", None)
    if service is None:
        pytest.fail("CapabilityLoaderService class missing from loader module")
    return service, module


def test_loader_skips_virtual_skill_docs_and_absent_examples(monkeypatch, caplog):
    service, module = _loader_service()
    monkeypatch.setattr(
        module.settings,
        "skills_dir",
        Path("/Users/sean/Coding/sideBar/backend/skills"),
    )
    caplog.set_level(logging.WARNING, logger="api.services.capabilities.loader")

    result = service.load_for_turn(
        selected_skill_ids=[
            "memory",
            "ui-theme",
            "web-search",
            "audio-transcribe",
            "web-crawler-policy",
            "youtube-transcribe",
        ],
        executable_skill_ids=[],
        tool_definition_resolver=lambda _skill_ids: [],
    )

    assert set(result.loaded_instruction_refs) == {
        "skills/audio-transcribe/SKILL.md",
        "skills/web-crawler-policy/SKILL.md",
        "skills/youtube-transcribe/SKILL.md",
    }
    assert result.loaded_examples == ()
    assert "Capability document missing" not in caplog.text
