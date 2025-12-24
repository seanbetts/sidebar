from datetime import date, datetime, timezone

from api.prompts import (
    resolve_template,
    build_system_prompt,
    build_first_message_prompt,
    build_recent_activity_block,
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
    ):
        self.name = name
        self.gender = gender
        self.pronouns = pronouns
        self.job_title = job_title
        self.employer = employer
        self.date_of_birth = date_of_birth
        self.communication_style = communication_style
        self.working_relationship = working_relationship


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
    now = datetime(2025, 1, 2, 13, 45, tzinfo=timezone.utc)
    prompt = build_system_prompt(settings, "London", now)
    assert "Sam's personal AI assistant" in prompt
    assert "Current date: 2025-01-02" in prompt
    assert "Current time: 13:45 UTC" in prompt
    assert "Location: London" in prompt


def test_build_first_message_prompt_includes_profile() -> None:
    settings = DummySettings(
        name="Sam",
        gender="male",
        pronouns="he/him",
        job_title="Engineer",
        employer="Acme",
        date_of_birth=date(2000, 1, 2),
    )
    now = datetime(2025, 1, 2, 9, 0, tzinfo=timezone.utc)
    prompt = build_first_message_prompt(settings, "macOS", now)
    assert "I am Sam." in prompt
    assert "I am male." in prompt
    assert "My pronouns are he/him." in prompt
    assert "I am 25 years old." in prompt
    assert "I use a macOS." in prompt
    assert "I am the Engineer at Acme." in prompt


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
    block = build_recent_activity_block(notes, websites, conversations)
    assert "<recent_activity>" in block
    assert "Notes opened today:" in block
    assert "Websites opened today:" in block
    assert "Chats active today:" in block
    assert "Daily log" in block
    assert "folder: work" in block
    assert "Docs" in block
    assert "domain: example.com" in block
    assert "url: https://example.com/docs" in block
    assert "Project X" in block
    assert "messages: 4" in block
