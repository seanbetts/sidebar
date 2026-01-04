import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

from api.db.base import Base
from api.exceptions import ConflictError, NotFoundError
from api.services.memory_service import MemoryService


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


def test_create_and_read_memory(db_session):
    memory = MemoryService.create_memory(db_session, "user-1", "/notes/test.md", "Hello")
    fetched = MemoryService.get_memory(db_session, "user-1", memory.id)

    assert fetched.path == "notes/test.md"
    assert fetched.content == "Hello"


def test_update_memory(db_session):
    memory = MemoryService.create_memory(db_session, "user-1", "/notes/test.md", "Hello")
    updated = MemoryService.update_memory(
        db_session,
        "user-1",
        memory.id,
        path="/notes/renamed.md",
        content="Updated",
    )

    assert updated.path == "notes/renamed.md"
    assert updated.content == "Updated"


def test_update_memory_conflict(db_session):
    first = MemoryService.create_memory(db_session, "user-1", "/notes/first.md", "One")
    MemoryService.create_memory(db_session, "user-1", "/notes/second.md", "Two")

    with pytest.raises(ConflictError):
        MemoryService.update_memory(db_session, "user-1", first.id, path="/notes/second.md")


def test_delete_memory(db_session):
    memory = MemoryService.create_memory(db_session, "user-1", "/notes/test.md", "Hello")
    MemoryService.delete_memory(db_session, "user-1", memory.id)

    with pytest.raises(NotFoundError):
        MemoryService.get_memory(db_session, "user-1", memory.id)
