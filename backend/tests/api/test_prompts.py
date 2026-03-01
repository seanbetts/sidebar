from datetime import UTC, date, datetime

from api.services.agent.prompt import sections as prompt_sections
from api.services.agent.prompt.sections import (
    CONTEXT_GUIDANCE_TEMPLATE,
    build_assistant_identity_block,
    build_assistant_soul_block,
    build_first_message_prompt,
    build_open_context_block,
    build_recent_activity_block,
    build_system_prompt,
    resolve_template,
)


class DummySettings:
    def __init__(
        self,
        name: str | None = None,
        gender: str | None = None,
        pronouns: str | None = None,
        job_title: str | None = None,
        employer: str | None = None,
        date_of_birth: date | None = None,
        communication_style: str | None = None,
        working_relationship: str | None = None,
        location: str | None = None,
        assistant_identity: dict | None = None,
        tasks_ai_snapshot: str | None = None,
    ):
        self.name = name
        self.gender = gender
        self.pronouns = pronouns
        self.job_title = job_title
        self.employer = employer
        self.date_of_birth = date_of_birth
        self.communication_style = communication_style
        self.working_relationship = working_relationship
        self.location = location
        self.assistant_identity = assistant_identity
        self.tasks_ai_snapshot = tasks_ai_snapshot


def test_resolve_template_keeps_unknown_tokens() -> None:
    template = "Hello {name}, meet {unknown}."
    result = resolve_template(template, {"name": "Sam"})
    assert result == "Hello Sam, meet {unknown}."


def test_resolve_template_blanks_unknown_tokens() -> None:
    template = "Hello {name}, meet {unknown}."
    result = resolve_template(template, {"name": "Sam"}, keep_unknown=False)
    assert result == "Hello Sam, meet ."


def test_build_system_prompt_renders_variables() -> None:
    settings = DummySettings(name="Sam")
    now = datetime(2025, 1, 2, 13, 45, tzinfo=UTC)
    prompt = build_system_prompt(settings, "London", None, None, now)
    assert "Sam's personal AI assistant" in prompt
    assert "Current date: 2025-01-02" in prompt
    assert "Current time: 13:45 UTC" in prompt
    assert "Home location: Unknown" in prompt
    assert "Current location: London" in prompt
    assert "Current weather at current location: Unavailable" in prompt


def test_build_system_prompt_wraps_tasks_with_blank_lines() -> None:
    settings = DummySettings(
        name="Sam",
        tasks_ai_snapshot="### Today\n\n- [ ] Ship release",
    )
    now = datetime(2025, 1, 2, 13, 45, tzinfo=UTC)
    prompt = build_system_prompt(settings, "London", None, None, now)
    assert "<tasks>\n\n### Today" in prompt
    assert "Ship release" in prompt
    assert "\n\n</tasks>" in prompt


def test_build_first_message_prompt_includes_profile() -> None:
    settings = DummySettings(
        name="Sam",
        gender="male",
        pronouns="he/him",
        job_title="Engineer",
        employer="Acme",
        date_of_birth=date(2000, 1, 2),
    )
    now = datetime(2025, 1, 2, 9, 0, tzinfo=UTC)
    prompt = build_first_message_prompt(settings, "macOS", now)
    assert "I am Sam." in prompt
    assert "I am male." in prompt
    assert "My pronouns are he/him." in prompt
    assert "I am 25 years old." in prompt
    assert "I use macOS." in prompt
    assert "I am the Engineer at Acme." in prompt


def test_build_assistant_identity_block_defaults() -> None:
    settings = DummySettings()
    block = build_assistant_identity_block(settings)
    assert "<assistant_identity>" in block
    assert "Name: sideBar" in block
    assert "Tone: Pragmatic, direct, and collaborative." in block


def test_build_assistant_identity_block_uses_overrides() -> None:
    settings = DummySettings(
        assistant_identity={
            "name": "Navigator",
            "tone": "Calm and technical.",
            "values": "Accuracy and speed.",
            "boundaries": "Never hallucinate.",
        }
    )
    block = build_assistant_identity_block(settings)
    assert "Name: Navigator" in block
    assert "Tone: Calm and technical." in block
    assert "Values: Accuracy and speed." in block
    assert "Boundaries: Never hallucinate." in block


def test_build_assistant_soul_block_defaults() -> None:
    settings = DummySettings()
    block = build_assistant_soul_block(settings)
    assert "<assistant_soul>" in block
    assert "Purpose:" in block
    assert "Bootstrap guidance:" in block


def test_build_assistant_soul_block_uses_overrides() -> None:
    settings = DummySettings()
    settings.assistant_soul = {
        "purpose": "Help me execute deliberately.",
        "operating_principles": "Be concise and explicit.",
        "adaptation_policy": "Adapt on repeated feedback.",
        "success_signals": "Less rework.",
    }
    block = build_assistant_soul_block(settings)
    assert "Purpose: Help me execute deliberately." in block
    assert "Operating principles: Be concise and explicit." in block
    assert "Adaptation policy: Adapt on repeated feedback." in block
    assert "Success signals: Less rework." in block
    assert "Bootstrap guidance:" not in block


def test_build_recent_activity_block() -> None:
    notes = [
        {
            "id": "note-1",
            "title": "Daily log",
            "last_opened_at": "2025-01-02T09:00:00Z",
            "folder": "work",
        }
    ]
    websites = [
        {
            "id": "web-1",
            "title": "Docs",
            "last_opened_at": "2025-01-02T10:00:00Z",
            "domain": "example.com",
            "url": "https://example.com/docs",
        }
    ]
    conversations = [
        {
            "id": "chat-1",
            "title": "Project X",
            "last_opened_at": "2025-01-02T11:00:00Z",
            "message_count": 4,
        }
    ]
    files = [
        {
            "id": "file-1",
            "filename": "gentle-guide.pdf",
            "last_opened_at": "2025-01-02T12:00:00Z",
            "mime": "application/pdf",
        }
    ]
    block = build_recent_activity_block(notes, websites, conversations, files)
    assert "<recent_activity>" in block
    assert "<recent_activity>\n\n" in block
    assert "Notes opened today:" in block
    assert "Websites opened today:" in block
    assert "Chats active today:" in block
    assert "Files opened today:" in block
    assert "Daily log" in block
    assert "folder: work" in block
    assert "Docs" in block
    assert "domain: example.com" in block
    assert "url: https://example.com/docs" in block
    assert "Project X" in block
    assert "messages: 4" in block
    assert "gentle-guide.pdf" in block
    assert "\n\n</recent_activity>" in block


def test_build_recent_activity_block_empty() -> None:
    block = build_recent_activity_block([], [], [], [])
    assert "No items have been opened today." in block


def test_build_open_context_block_truncates() -> None:
    note = {
        "id": "note-1",
        "title": "Draft",
        "path": "notes/draft.md",
        "content": "z" * 10,
        "plain_text": "x" * 10,
    }
    website = {
        "id": "web-1",
        "title": "Spec",
        "domain": "example.com",
        "url": "https://example.com/spec",
        "content": "y" * 10,
    }
    block = build_open_context_block(note, website, max_chars=5)
    assert "<current_open>" in block
    assert "<current_open>\n\n" in block
    assert "Note currently open:" in block
    assert "Website currently open:" in block
    assert "xxxxx" in block
    assert "zzzzz" not in block
    assert "yyyyy" in block
    assert "\n\n</current_open>" in block


def test_build_open_context_block_empty() -> None:
    block = build_open_context_block(None, None)
    assert "No items are currently open." in block


def test_build_open_context_block_runs_note_canonicality_diagnostics(monkeypatch) -> None:
    captured: dict[str, object] = {}

    def _fake_diagnose(**kwargs):
        captured.update(kwargs)
        return []

    monkeypatch.setattr(
        prompt_sections,
        "diagnose_note_read_canonicality",
        _fake_diagnose,
    )

    note = {
        "id": "note-1",
        "title": "Draft",
        "path": "notes/draft.md",
        "content": "abc",
        "plain_text": "Body",
        "content_format": "rtf",
    }
    build_open_context_block(note, None)

    assert captured["context"] == "prompt.build_open_context_block"
    assert captured["note_id"] == "note-1"
    assert captured["require_content"] is True
    assert captured["metadata"] == {"content_format": "rtf", "plain_text": "Body"}


def test_context_guidance_template_renders_name() -> None:
    rendered = resolve_template(CONTEXT_GUIDANCE_TEMPLATE, {"name": "Sam"})
    assert "Sam has been working on today" in rendered
