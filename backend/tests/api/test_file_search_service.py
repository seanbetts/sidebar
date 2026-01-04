import re
import uuid
from contextlib import contextmanager

import pytest
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

from api.db.base import Base
from api.services.file_ingestion_service import FileIngestionService
from api.services.file_search_service import FileSearchService


@pytest.fixture
def db_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(isolation_level="AUTOCOMMIT")
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


def test_search_entries_name_match(db_session, monkeypatch):
    @contextmanager
    def fake_session_for_user(_user_id):
        yield db_session

    monkeypatch.setattr(
        "api.services.file_search_service.session_for_user",
        fake_session_for_user,
    )

    FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="a.txt",
        path="docs/a.txt",
        mime_original="text/plain",
        size_bytes=1,
    )
    FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="b.txt",
        path="other/b.txt",
        mime_original="text/plain",
        size_bytes=1,
    )

    pattern = re.compile(r"^a\.txt$")
    results = FileSearchService.search_entries(
        "user-1",
        "docs",
        name_pattern=pattern,
        content_pattern=None,
        max_results=10,
    )

    assert len(results) == 1
    assert results[0]["path"] == "docs/a.txt"
    assert results[0]["match_type"] == "name"
