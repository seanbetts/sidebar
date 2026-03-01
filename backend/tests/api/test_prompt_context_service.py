from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from api.db.base import Base
from api.models.conversation import Conversation
from api.models.note import Note
from api.models.user_settings import UserSettings
from api.models.website import Website
from api.services.agent.prompt.composer import PromptContextService


def test_prompt_context_service_order_and_truncation(test_db):
    Base.metadata.create_all(bind=test_db.connection())
    test_db.execute(
        text(
            "ALTER TABLE user_settings "
            "ADD COLUMN IF NOT EXISTS assistant_identity jsonb"
        )
    )
    test_db.execute(
        text(
            "ALTER TABLE user_settings "
            "ADD COLUMN IF NOT EXISTS assistant_soul jsonb"
        )
    )
    test_db.commit()
    now = datetime(2025, 1, 2, 12, 0, tzinfo=UTC)
    user_id = "user-1"

    settings = UserSettings(user_id=user_id, name="Sam")
    test_db.add(settings)

    note = Note(
        user_id=user_id,
        title="Daily Log",
        content="Note body",
        metadata_={"folder": "work"},
        last_opened_at=now,
    )
    website = Website(
        user_id=user_id,
        url="https://example.com",
        url_full="https://example.com/docs",
        domain="example.com",
        title="Docs",
        content="Website body",
        last_opened_at=now,
    )
    conversation = Conversation(
        user_id=user_id,
        title="Project X",
        updated_at=now,
        message_count=3,
    )
    test_db.add_all([note, website, conversation])
    test_db.commit()

    open_context = {
        "note": {
            "id": str(note.id),
            "title": note.title,
            "path": "notes/daily-log.md",
            "content": "ignored content",
            "plain_text": "x" * (PromptContextService.MAX_SYSTEM_PROMPT_CHARS + 1000),
        },
        "website": {
            "id": str(website.id),
            "title": website.title,
            "url": website.url_full or website.url,
            "domain": website.domain,
            "content": "Website body",
        },
    }

    prompt_bundle = PromptContextService.build_prompts(
        db=test_db,
        user_id=user_id,
        open_context=open_context,
        attachments=None,
        user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        current_location_levels={"locality": "Bealbury", "country": "United Kingdom"},
        now=now,
    )
    system_prompt = prompt_bundle["system_prompt"]["text"]
    first_message = prompt_bundle["first_message_prompt"]["text"]

    assert "<message_context>" in system_prompt
    idx_message = system_prompt.index("<message_context>")
    idx_identity = system_prompt.index("<assistant_identity>")
    idx_soul = system_prompt.index("<assistant_soul>")
    idx_response_style = system_prompt.index("<response_style>")
    idx_guidance = system_prompt.index("<context_guidance>")
    idx_open = system_prompt.index("<current_open>")
    idx_recent = system_prompt.index("<recent_activity>")
    assert (
        idx_message
        < idx_identity
        < idx_soul
        < idx_response_style
        < idx_guidance
        < idx_open
        < idx_recent
    )

    assert len(system_prompt) <= PromptContextService.MAX_SYSTEM_PROMPT_CHARS
    assert "</current_open>" in system_prompt
    assert "</recent_activity>" in system_prompt
    assert prompt_bundle["system_prompt"]["truncated"] is True
    assert "I use macOS." in first_message
    assert prompt_bundle["report"]["system_prompt"]["sections"] == [
        {
            "id": "message_context",
            "title": "Message Context",
            "source": "system_template",
            "chars": len(prompt_bundle["system_prompt"]["sections"][0]["content"]),
        },
        {
            "id": "assistant_identity",
            "title": "Assistant Identity",
            "source": "assistant_identity",
            "chars": len(prompt_bundle["system_prompt"]["sections"][1]["content"]),
        },
        {
            "id": "assistant_soul",
            "title": "Assistant Soul",
            "source": "assistant_soul",
            "chars": len(prompt_bundle["system_prompt"]["sections"][2]["content"]),
        },
        {
            "id": "response_style",
            "title": "Response Style",
            "source": "response_style",
            "chars": len(prompt_bundle["system_prompt"]["sections"][3]["content"]),
        },
        {
            "id": "context_guidance",
            "title": "Context Guidance",
            "source": "context_guidance_template",
            "chars": len(prompt_bundle["system_prompt"]["sections"][4]["content"]),
        },
        {
            "id": "current_open",
            "title": "Current Open Context",
            "source": "open_context",
            "chars": len(prompt_bundle["system_prompt"]["sections"][5]["content"]),
        },
        {
            "id": "recent_activity",
            "title": "Recent Activity",
            "source": "recent_activity",
            "chars": len(prompt_bundle["system_prompt"]["sections"][6]["content"]),
        },
    ]


def test_recent_activity_cache_hit(test_db):
    PromptContextService._recent_activity_cache.clear()
    Base.metadata.create_all(bind=test_db.connection())
    now = datetime(2025, 2, 1, 9, 0, tzinfo=UTC)
    user_id = "user-1"

    note = Note(
        user_id=user_id,
        title="Morning Notes",
        content="Note body",
        metadata_={"folder": "work"},
        last_opened_at=now,
    )
    test_db.add(note)
    test_db.commit()

    first_notes, _, _, _ = PromptContextService._get_recent_activity(
        test_db, user_id, now
    )

    new_note = Note(
        user_id=user_id,
        title="Late Add",
        content="Extra",
        metadata_={"folder": "work"},
        last_opened_at=now + timedelta(minutes=1),
    )
    test_db.add(new_note)
    test_db.commit()

    cached_notes, _, _, _ = PromptContextService._get_recent_activity(
        test_db, user_id, now + timedelta(minutes=1)
    )

    assert len(first_notes) == len(cached_notes)
    assert {item["title"] for item in cached_notes} == {"Morning Notes"}


def test_recent_activity_cache_expiry(test_db):
    PromptContextService._recent_activity_cache.clear()
    Base.metadata.create_all(bind=test_db.connection())
    now = datetime(2025, 2, 1, 9, 0, tzinfo=UTC)
    user_id = "user-1"

    note = Note(
        user_id=user_id,
        title="Morning Notes",
        content="Note body",
        metadata_={"folder": "work"},
        last_opened_at=now,
    )
    test_db.add(note)
    test_db.commit()

    PromptContextService._get_recent_activity(test_db, user_id, now)

    new_note = Note(
        user_id=user_id,
        title="Afternoon Notes",
        content="Extra",
        metadata_={"folder": "work"},
        last_opened_at=now + timedelta(minutes=10),
    )
    test_db.add(new_note)
    test_db.commit()

    later = now + PromptContextService.RECENT_ACTIVITY_CACHE_TTL + timedelta(seconds=1)
    refreshed_notes, _, _, _ = PromptContextService._get_recent_activity(
        test_db, user_id, later
    )

    assert {item["title"] for item in refreshed_notes} == {
        "Morning Notes",
        "Afternoon Notes",
    }


def test_recent_activity_uses_user_timezone_for_day_boundary(test_db):
    PromptContextService._recent_activity_cache.clear()
    Base.metadata.create_all(bind=test_db.connection())
    user_id = "user-timezone"
    now_utc = datetime(2025, 1, 2, 0, 30, tzinfo=UTC)
    note_time = datetime(2025, 1, 1, 23, 30, tzinfo=UTC)

    test_db.add(UserSettings(user_id=user_id, name="Sam"))
    test_db.add(
        Note(
            user_id=user_id,
            title="Late Night Note",
            content="Body",
            metadata_={"folder": "work"},
            last_opened_at=note_time,
        )
    )
    test_db.commit()

    prompt_bundle = PromptContextService.build_prompts(
        db=test_db,
        user_id=user_id,
        open_context=None,
        attachments=None,
        user_agent=None,
        current_timezone="America/Los_Angeles",
        now=now_utc,
    )

    system_prompt = prompt_bundle["system_prompt"]["text"]
    assert "Late Night Note" in system_prompt
    assert "Current time: 16:30 PST" in system_prompt
