from importlib import import_module

import pytest

from api.services.agent.skills.catalog import SkillCatalogService


def _write_skill(skill_root, skill_id: str, metadata_block: str = "") -> None:
    skill_dir = skill_root / skill_id
    skill_dir.mkdir(parents=True, exist_ok=True)
    frontmatter = (
        "---\n"
        "name: Placeholder\n"
        "description: Placeholder description\n"
        f"{metadata_block}"
        "---\n"
    )
    (skill_dir / "SKILL.md").write_text(
        frontmatter,
        encoding="utf-8",
    )


def test_list_skills_uses_updated_display_metadata(tmp_path) -> None:
    skills_dir = tmp_path / "skills"
    skills_dir.mkdir(parents=True)

    for skill_id in [
        "files",
        "notes",
        "tasks",
        "web-save",
        "audio-transcribe",
        "youtube-download",
        "youtube-transcribe",
        "prompt-preview",
        "settings-other-preferences",
        "assistant-identity",
        "assistant-soul",
    ]:
        if skill_id == "audio-transcribe":
            _write_skill(
                skills_dir,
                skill_id,
                metadata_block=(
                    "metadata:\n"
                    "  long_description: Long detail\n"
                    "  how_it_works: Friendly explanation\n"
                    "  requirements:\n"
                    "    - OpenAI API key\n"
                    "    - ffmpeg installed for local audio processing\n"
                    "    - Internet connection\n"
                    "  version: 1.0.0\n"
                    "  updated_at: 2026-02-22\n"
                ),
            )
        else:
            _write_skill(skills_dir, skill_id)

    skills = SkillCatalogService.list_skills(skills_dir)
    by_id = {str(skill["id"]): skill for skill in skills}

    assert str(by_id["files"]["description"]) == "Search, read, write, rename, pin and delete files"
    assert by_id["files"]["legacy_ids"] == []
    assert by_id["files"]["tier"] == "standard"
    assert by_id["files"]["installable"] is False
    assert by_id["files"]["default_enabled"] is True
    assert by_id["audio-transcribe"]["tier"] == "store"
    assert by_id["audio-transcribe"]["installable"] is True
    assert "required_toolsets" in by_id["audio-transcribe"]
    assert isinstance(by_id["audio-transcribe"]["required_toolsets"], list)
    assert by_id["audio-transcribe"]["required_toolsets"]
    assert by_id["audio-transcribe"]["long_description"] == "Long detail"
    assert by_id["audio-transcribe"]["how_it_works"] == "Friendly explanation"
    assert by_id["audio-transcribe"]["requirements"] == ["Internet connection"]
    assert by_id["audio-transcribe"]["version"] == "1.0.0"
    assert by_id["audio-transcribe"]["updated_at"] == "2026-02-22"
    assert by_id["audio-transcribe"]["install_count"] is None
    assert by_id["audio-transcribe"]["upvotes"] is None
    assert by_id["audio-transcribe"]["downvotes"] is None
    assert by_id["audio-transcribe"]["current_user_vote"] is None
    expected_ids = {
        "assistant-identity",
        "assistant-soul",
        "audio-transcribe",
        "files",
        "memory",
        "notes",
        "prompt-preview",
        "settings-other-preferences",
        "tasks",
        "ui-theme",
        "web-save",
        "web-search",
        "youtube-download",
        "youtube-transcribe",
    }
    assert set(by_id) == expected_ids
    assert by_id["prompt-preview"]["tier"] == "standard"
    assert by_id["prompt-preview"]["installable"] is False
    assert by_id["settings-other-preferences"]["tier"] == "standard"
    assert by_id["settings-other-preferences"]["installable"] is False
    assert str(by_id["settings-other-preferences"]["name"]) == "Settings"
    assert by_id["audio-transcribe"]["provider_dependency"] == "openai"
    assert by_id["audio-transcribe"]["credential_requirements"]
    assert (
        str(by_id["audio-transcribe"]["description"])
        == "Transcribe audio files into text and save the transcripts"
    )
    assert str(by_id["youtube-download"]["description"]) == "Save YouTube videos"
    assert (
        str(by_id["youtube-transcribe"]["description"])
        == "Transcribe YouTube videos into text and save the transcripts"
    )
    assert (
        str(by_id["notes"]["description"])
        == "Search, read, create, update, rename, pin, move, manage folder, archive and delete notes"
    )
    assert (
        str(by_id["tasks"]["description"])
        == "Search, read, create, complete, defer, organize and delete tasks"
    )
    assert str(by_id["web-save"]["description"]) == "Save webpages as clean markdown"
    assert (
        str(by_id["web-search"]["description"])
        == "Search the live web for up-to-date information"
    )
    assert str(by_id["ui-theme"]["description"]) == "Allow {name} to switch between light and dark mode"
    assert str(by_id["memory"]["description"]) == "Store and manage persistent memories"

    assert bool(by_id["assistant-identity"]["user_toggleable"]) is False
    assert bool(by_id["assistant-soul"]["user_toggleable"]) is False
    assert all(not str(skill["description"]).endswith(".") for skill in by_id.values())


def test_catalog_version_exposed() -> None:
    assert SkillCatalogService.catalog_version() == 9


def test_capability_registry_exposes_code_backed_contract() -> None:
    try:
        module = import_module("api.services.capabilities.registry")
    except ModuleNotFoundError:
        pytest.fail(
            "Capability registry module missing: api.services.capabilities.registry"
        )

    registry_loader = getattr(module, "CapabilityRegistry", None)
    if registry_loader is None:
        pytest.fail("CapabilityRegistry class missing from registry module")

    records = registry_loader.list_capabilities()
    by_skill_id = {record.skill_id: record for record in records}
    assert "audio-transcribe" in by_skill_id

    audio_transcribe = by_skill_id["audio-transcribe"]
    assert audio_transcribe.required_toolsets
    assert audio_transcribe.instruction_ref
    assert isinstance(audio_transcribe.token_estimate, int)
    assert audio_transcribe.token_estimate > 0
    assert isinstance(audio_transcribe.tags, tuple)
    assert isinstance(audio_transcribe.triggers, tuple)


def test_capability_registry_loads_without_db_access(monkeypatch) -> None:
    try:
        module = import_module("api.services.capabilities.registry")
    except ModuleNotFoundError:
        pytest.fail(
            "Capability registry module missing: api.services.capabilities.registry"
        )

    registry_loader = getattr(module, "CapabilityRegistry", None)
    if registry_loader is None:
        pytest.fail("CapabilityRegistry class missing from registry module")

    def _unexpected_db_access(*_args, **_kwargs):
        raise AssertionError("registry should not require database access")

    monkeypatch.setattr(
        SkillCatalogService,
        "_read_frontmatter",
        staticmethod(_unexpected_db_access),
    )

    records = registry_loader.list_capabilities()
    assert records
