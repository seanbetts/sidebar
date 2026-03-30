import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import text

from api.db.base import Base
from api.models.conversation import Conversation
from api.models.file_ingestion import IngestedFile
from api.models.note import Note
from api.models.user_settings import UserSettings
from api.models.website import Website
from api.services.agent.prompt import composer as prompt_composer
from api.services.agent.prompt.composer import PromptContextService
from api.services.notes_document_types import note_document_from_plain_text


def _ensure_user_settings_prompt_columns(test_db):
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


def test_prompt_context_service_order_and_truncation(test_db):
    Base.metadata.create_all(bind=test_db.connection())
    _ensure_user_settings_prompt_columns(test_db)
    now = datetime(2025, 1, 2, 12, 0, tzinfo=UTC)
    user_id = "user-1"

    settings = UserSettings(user_id=user_id, name="Sam")
    test_db.add(settings)

    note = Note(
        user_id=user_id,
        title="Daily Log",
        document=note_document_from_plain_text("Note body"),
        plain_text="Note body",
        folder_path="work",
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
    assert "<assistant_identity>" in system_prompt
    assert "<assistant_soul>" in system_prompt
    assert "<response_style>" not in system_prompt
    assert "<context_guidance>" in system_prompt
    assert "<current_open>" in system_prompt
    assert "<recent_activity>" in system_prompt

    system_section_ids = [
        section["id"] for section in prompt_bundle["system_prompt"]["sections"]
    ]
    assert system_section_ids.index("message_context") < system_section_ids.index(
        "assistant_identity"
    )
    assert system_section_ids.index("assistant_identity") < system_section_ids.index(
        "assistant_soul"
    )
    assert system_section_ids.index("assistant_soul") < system_section_ids.index(
        "response_style"
    )
    assert system_section_ids.index("response_style") < system_section_ids.index(
        "context_guidance"
    )
    assert system_section_ids.index("context_guidance") < system_section_ids.index(
        "current_open"
    )
    assert system_section_ids.index("current_open") < system_section_ids.index(
        "recent_activity"
    )

    assert len(system_prompt) <= PromptContextService.MAX_SYSTEM_PROMPT_CHARS
    assert "</current_open>" in system_prompt
    assert "</recent_activity>" in system_prompt
    assert prompt_bundle["system_prompt"]["truncated"] is True
    assert prompt_bundle["system_prompt"]["truncated_by_section_limits"] is True
    assert prompt_bundle["system_prompt"]["truncated_by_budget"] is False
    assert (
        prompt_bundle["system_prompt"]["raw_total_chars"]
        > prompt_bundle["system_prompt"]["constrained_total_chars"]
    )
    assert "I use macOS." in first_message
    assert prompt_bundle["report"]["system_prompt"]["sections"] == [
        {
            "id": section["id"],
            "title": section["title"],
            "source": section["source"],
            "chars": len(section["content"]),
        }
        for section in prompt_bundle["system_prompt"]["sections"]
    ]

    assert prompt_bundle["report"]["system_prompt"]["truncated_by_section_limits"] is True
    assert prompt_bundle["report"]["system_prompt"]["truncated_by_budget"] is False


def test_prompt_context_service_strict_mode_allows_section_capped_prompt(test_db):
    Base.metadata.create_all(bind=test_db.connection())
    _ensure_user_settings_prompt_columns(test_db)
    now = datetime(2025, 1, 2, 12, 0, tzinfo=UTC)
    user_id = "user-strict-sections"

    test_db.add(UserSettings(user_id=user_id, name="Sam"))
    test_db.commit()

    open_context = {
        "note": {
            "id": "note-1",
            "title": "Large Note",
            "path": "notes/large-note.md",
            "content": "ignored content",
            "plain_text": "x" * (PromptContextService.MAX_SYSTEM_PROMPT_CHARS + 1000),
        }
    }

    prompt_bundle = PromptContextService.build_prompts(
        db=test_db,
        user_id=user_id,
        open_context=open_context,
        attachments=None,
        user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        now=now,
        strict_system_prompt=True,
    )

    assert prompt_bundle["system_prompt"]["truncated"] is True
    assert prompt_bundle["system_prompt"]["truncated_by_section_limits"] is True
    assert prompt_bundle["system_prompt"]["truncated_by_budget"] is False
    assert (
        prompt_bundle["report"]["system_prompt"]["constrained_total_chars"]
        <= PromptContextService.MAX_SYSTEM_PROMPT_CHARS
    )


def test_prompt_context_service_strict_mode_rejects_budget_overflow(
    test_db, monkeypatch
):
    Base.metadata.create_all(bind=test_db.connection())
    _ensure_user_settings_prompt_columns(test_db)
    now = datetime(2025, 1, 2, 12, 0, tzinfo=UTC)
    user_id = "user-strict-budget"

    test_db.add(UserSettings(user_id=user_id, name="Sam"))
    test_db.commit()

    monkeypatch.setattr(
        prompt_composer,
        "build_system_prompt",
        lambda *_args, **_kwargs: "x"
        * (PromptContextService.MAX_SYSTEM_PROMPT_CHARS + 500),
    )

    with pytest.raises(ValueError) as error:
        PromptContextService.build_prompts(
            db=test_db,
            user_id=user_id,
            open_context=None,
            attachments=None,
            user_agent=None,
            now=now,
            strict_system_prompt=True,
        )

    message = str(error.value)
    assert message.startswith("System prompt exceeds maximum size (")
    assert message.endswith(" > 40000)")
    overflow_chars = int(message.split("(")[1].split(" >")[0])
    assert overflow_chars > PromptContextService.MAX_SYSTEM_PROMPT_CHARS


def test_prompt_context_service_includes_file_paths_in_current_open_and_attachments(
    test_db,
):
    Base.metadata.create_all(bind=test_db.connection())
    _ensure_user_settings_prompt_columns(test_db)
    now = datetime(2025, 2, 1, 9, 0, tzinfo=UTC)
    user_id = "user-files"

    test_db.add(UserSettings(user_id=user_id, name="Sam"))
    current_file = IngestedFile(
        user_id=user_id,
        filename_original="plan.md",
        path="Projects/plan.md",
        mime_original="text/markdown",
        size_bytes=42,
        sha256="abc",
        created_at=now,
        deleted_at=None,
    )
    attachment_file = IngestedFile(
        user_id=user_id,
        filename_original="brief.pdf",
        path="Uploads/brief.pdf",
        mime_original="application/pdf",
        size_bytes=84,
        sha256="def",
        created_at=now,
        deleted_at=None,
    )
    test_db.add_all([current_file, attachment_file])
    test_db.commit()

    prompt_bundle = PromptContextService.build_prompts(
        db=test_db,
        user_id=user_id,
        open_context={"file": {"id": str(current_file.id), "category": "workspace_file"}},
        attachments=[{"file_id": str(attachment_file.id), "category": "attachment"}],
        user_agent=None,
        now=now,
    )

    current_open = next(
        section
        for section in prompt_bundle["system_prompt"]["sections"]
        if section["id"] == "current_open"
    )["content"]

    assert "path: Projects/plan.md" in current_open
    assert "path: Uploads/brief.pdf" in current_open


def test_recent_activity_cache_hit(test_db):
    PromptContextService._recent_activity_cache.clear()
    Base.metadata.create_all(bind=test_db.connection())
    now = datetime(2025, 2, 1, 9, 0, tzinfo=UTC)
    user_id = "user-1"

    note = Note(
        user_id=user_id,
        title="Morning Notes",
        document=note_document_from_plain_text("Note body"),
        plain_text="Note body",
        folder_path="work",
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
        document=note_document_from_plain_text("Extra"),
        plain_text="Extra",
        folder_path="work",
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
        document=note_document_from_plain_text("Note body"),
        plain_text="Note body",
        folder_path="work",
        last_opened_at=now,
    )
    test_db.add(note)
    test_db.commit()

    PromptContextService._get_recent_activity(test_db, user_id, now)

    new_note = Note(
        user_id=user_id,
        title="Afternoon Notes",
        document=note_document_from_plain_text("Extra"),
        plain_text="Extra",
        folder_path="work",
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


def test_system_prompt_includes_product_knowledge_section(test_db):
    """The system prompt should include a product_knowledge section."""
    from api.services.knowledge.provider import init_docs_indexer

    # Build a minimal docs directory
    with tempfile.TemporaryDirectory() as tmp:
        docs_root = Path(tmp)
        (docs_root / "intro.md").write_text(
            "---\ntitle: Introduction\nsummary: What sideBar is.\n"
            "tags: [manual]\naudience: user\nsurfaces: [internal-knowledge]\n---\n\nContent.\n"
        )
        init_docs_indexer(docs_root)

        Base.metadata.create_all(bind=test_db.connection())
        _ensure_user_settings_prompt_columns(test_db)
        user_id = "user-product-knowledge-test"
        settings = UserSettings(user_id=user_id, name="Test User")
        test_db.add(settings)
        test_db.commit()

        result = PromptContextService.build_prompts(
            db=test_db,
            user_id=user_id,
            open_context=None,
            attachments=None,
            user_agent="test",
        )
        section_ids = [s["id"] for s in result["system_prompt"]["sections"]]
        assert "product_knowledge" in section_ids

    import api.services.knowledge.provider as _knowledge_provider
    _knowledge_provider._indexer = None


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
            document=note_document_from_plain_text("Body"),
            plain_text="Body",
            folder_path="work",
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
