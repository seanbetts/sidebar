from api.services.agent.skills.catalog import SkillCatalogService


def _write_skill(skill_root, skill_id: str) -> None:
    skill_dir = skill_root / skill_id
    skill_dir.mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(
        "---\nname: Placeholder\ndescription: Placeholder description\n---\n",
        encoding="utf-8",
    )


def test_list_skills_uses_updated_display_metadata(tmp_path) -> None:
    skills_dir = tmp_path / "skills"
    skills_dir.mkdir(parents=True)

    for skill_id in [
        "fs",
        "notes",
        "tasks",
        "web-save",
        "audio-transcribe",
        "youtube-download",
        "youtube-transcribe",
        "assistant-identity",
        "assistant-soul",
    ]:
        _write_skill(skills_dir, skill_id)

    skills = SkillCatalogService.list_skills(skills_dir)
    by_id = {str(skill["id"]): skill for skill in skills}

    assert str(by_id["fs"]["description"]) == "Search, read, write, rename, pin and delete files"
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
    assert bool(by_id["assistant-identity"]["show_required_badge"]) is False
    assert bool(by_id["assistant-soul"]["show_required_badge"]) is False
    assert all(not str(skill["description"]).endswith(".") for skill in by_id.values())
