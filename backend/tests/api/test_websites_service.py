import uuid
from datetime import UTC, datetime, timedelta

import pytest
from api.db.base import Base
from api.exceptions import ConflictError
from api.schemas.filters import WebsiteFilters
from api.services.websites_service import WebsitesService
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker


@pytest.fixture
def db_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    )
    schema = f"test_{uuid.uuid4().hex}"

    connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    connection.execute(text(f'SET search_path TO "{schema}"'))
    Base.metadata.create_all(bind=connection)

    Session = sessionmaker(bind=connection)
    session = Session()

    try:
        yield session
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()


def test_save_and_read_website(db_session):
    website = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/path?query=1",
        title="Example",
        content="Content",
        source="https://example.com/path?query=1",
    )

    assert website.url == "https://example.com/path"
    assert website.domain == "example.com"

    fetched = WebsitesService.get_website(
        db_session, "test_user", website.id, mark_opened=True
    )
    assert fetched is not None
    assert fetched.title == "Example"
    assert fetched.last_opened_at is not None


def test_save_website_derives_reading_time_from_content(db_session):
    website = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/reading-time",
        title="Reading Time",
        content="---\nreading_time: '104 min'\n---\n\nBody",
        source="https://example.com/reading-time",
    )

    assert website.reading_time == "1 hr 44 mins"
    assert (website.metadata_ or {}).get("reading_time") == "1 hr 44 mins"


def test_update_website_recomputes_reading_time(db_session):
    website = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/update-reading-time",
        title="Reading Time",
        content="---\nreading_time: '5 min'\n---\n\nBody",
        source="https://example.com/update-reading-time",
    )
    assert website.reading_time == "5 mins"

    updated = WebsitesService.update_website(
        db_session,
        "test_user",
        website.id,
        content="---\nreading_time: '30 min'\n---\n\nBody",
    )

    assert updated.reading_time == "30 mins"
    assert (updated.metadata_ or {}).get("reading_time") == "30 mins"


def test_update_pinned_and_archived(db_session):
    website = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/a",
        title="A",
        content="Content",
        source="https://example.com/a",
    )

    archived = WebsitesService.update_archived(
        db_session, "test_user", website.id, True
    )
    assert (archived.metadata_ or {}).get("archived") is True

    pinned = WebsitesService.update_pinned(db_session, "test_user", website.id, True)

    assert (pinned.metadata_ or {}).get("pinned") is True
    assert (pinned.metadata_ or {}).get("archived") is False


def test_update_pinned_assigns_next_order(db_session):
    site_a = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/a",
        title="Alpha",
        content="Content",
        source="https://example.com/a",
    )
    site_b = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/b",
        title="Beta",
        content="Content",
        source="https://example.com/b",
    )

    pinned_a = WebsitesService.update_pinned(db_session, "test_user", site_a.id, True)
    pinned_b = WebsitesService.update_pinned(db_session, "test_user", site_b.id, True)

    assert (pinned_a.metadata_ or {}).get("pinned_order") == 0
    assert (pinned_b.metadata_ or {}).get("pinned_order") == 1


def test_list_websites_filters(db_session):
    now = datetime.now(UTC)
    earlier = now - timedelta(days=3)

    site_a = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/a",
        title="Alpha",
        content="Content",
        source="https://example.com/a",
        published_at=earlier,
    )
    site_b = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.org/b",
        title="Beta",
        content="Content",
        source="https://example.org/b",
        published_at=now,
    )

    WebsitesService.update_pinned(db_session, "test_user", site_a.id, True)
    WebsitesService.update_archived(db_session, "test_user", site_b.id, True)

    pinned = WebsitesService.list_websites(
        db_session, "test_user", WebsiteFilters(pinned=True)
    )
    assert any(site.id == site_a.id for site in pinned)

    archived = WebsitesService.list_websites(
        db_session, "test_user", WebsiteFilters(archived=True)
    )
    assert any(site.id == site_b.id for site in archived)

    domain_filtered = WebsitesService.list_websites(
        db_session, "test_user", WebsiteFilters(domain="example.com")
    )
    assert all(site.domain == "example.com" for site in domain_filtered)

    published_filtered = WebsitesService.list_websites(
        db_session,
        "test_user",
        WebsiteFilters(
            published_after=earlier + timedelta(hours=1),
            published_before=now + timedelta(hours=1),
        ),
    )
    assert any(site.id == site_b.id for site in published_filtered)

    title_filtered = WebsitesService.list_websites(
        db_session, "test_user", WebsiteFilters(title_search="Alpha")
    )
    assert len(title_filtered) == 1
    assert title_filtered[0].id == site_a.id


def test_archived_summary(db_session):
    now = datetime.now(UTC)
    archived_at = now - timedelta(hours=3)

    archived_site = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/archived",
        title="Archived",
        content="Content",
        source="https://example.com/archived",
    )
    WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/active",
        title="Active",
        content="Content",
        source="https://example.com/active",
    )

    WebsitesService.update_archived(db_session, "test_user", archived_site.id, True)
    archived_site.updated_at = archived_at
    db_session.commit()

    summary = WebsitesService.archived_summary(db_session, "test_user")

    assert summary["archived_count"] == 1
    assert summary["archived_last_updated"] == archived_at.isoformat()


def test_update_website_conflict(db_session):
    website = WebsitesService.save_website(
        db_session,
        "test_user",
        url="https://example.com/conflict",
        title="Conflict",
        content="Content",
        source="https://example.com/conflict",
    )
    stale = website.updated_at - timedelta(seconds=10)

    with pytest.raises(ConflictError):
        WebsitesService.update_website(
            db_session,
            "test_user",
            website.id,
            title="Updated",
            client_updated_at=stale,
        )
