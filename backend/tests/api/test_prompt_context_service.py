from datetime import datetime, timezone, timedelta

from api.db.base import Base
from api.models.conversation import Conversation
from api.models.note import Note
from api.models.user_settings import UserSettings
from api.models.website import Website
from api.services.prompt_context_service import PromptContextService


def test_prompt_context_service_order_and_truncation(test_db):
    Base.metadata.create_all(bind=test_db.connection())
    now = datetime(2025, 1, 2, 12, 0, tzinfo=timezone.utc)
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
            "content": "x" * (PromptContextService.MAX_SYSTEM_PROMPT_CHARS + 1000),
        },
        "website": {
            "id": str(website.id),
            "title": website.title,
            "url": website.url_full or website.url,
            "domain": website.domain,
            "content": "Website body",
        },
    }

    system_prompt, first_message = PromptContextService.build_prompts(
        db=test_db,
        user_id=user_id,
        open_context=open_context,
        attachments=None,
        user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        current_location_levels={"locality": "Bealbury", "country": "United Kingdom"},
        now=now,
    )

    assert "<message_context>" in system_prompt
    idx_message = system_prompt.index("<message_context>")
    idx_guidance = system_prompt.index("<context_guidance>")
    idx_open = system_prompt.index("<current_open>")
    idx_recent = system_prompt.index("<recent_activity>")
    assert idx_message < idx_guidance < idx_open < idx_recent

    assert len(system_prompt) <= PromptContextService.MAX_SYSTEM_PROMPT_CHARS
    assert "I use macOS." in first_message


def test_recent_activity_cache_hit(test_db):
    PromptContextService._recent_activity_cache.clear()
    Base.metadata.create_all(bind=test_db.connection())
    now = datetime(2025, 2, 1, 9, 0, tzinfo=timezone.utc)
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

    first_notes, _, _, _ = PromptContextService._get_recent_activity(test_db, user_id, now)

    new_note = Note(
        user_id=user_id,
        title="Late Add",
        content="Extra",
        metadata_={"folder": "work"},
        last_opened_at=now + timedelta(minutes=1),
    )
    test_db.add(new_note)
    test_db.commit()

    cached_notes, _, _, _ = PromptContextService._get_recent_activity(test_db, user_id, now + timedelta(minutes=1))

    assert len(first_notes) == len(cached_notes)
    assert {item["title"] for item in cached_notes} == {"Morning Notes"}


def test_recent_activity_cache_expiry(test_db):
    PromptContextService._recent_activity_cache.clear()
    Base.metadata.create_all(bind=test_db.connection())
    now = datetime(2025, 2, 1, 9, 0, tzinfo=timezone.utc)
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
    refreshed_notes, _, _, _ = PromptContextService._get_recent_activity(test_db, user_id, later)

    assert {item["title"] for item in refreshed_notes} == {"Morning Notes", "Afternoon Notes"}
