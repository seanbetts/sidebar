import uuid
from datetime import timedelta

from api.db.base import Base
from api.services.file_ingestion_service import FileIngestionService
from api.services.files_sync_service import FilesSyncService
from api.services.notes_service import NotesService
from api.services.notes_sync_service import NotesSyncService
from api.services.websites_service import WebsitesService
from api.services.websites_sync_service import WebsitesSyncService
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker


def _make_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    )
    schema = f"test_{uuid.uuid4().hex}"
    connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    connection.execute(text(f'SET search_path TO "{schema}"'))
    Base.metadata.create_all(bind=connection)
    Session = sessionmaker(bind=connection)
    return connection, Session(), schema


def test_notes_sync_conflict(test_db_engine):
    connection, session, schema = _make_session(test_db_engine)
    try:
        note = NotesService.create_note(session, "user-1", "# Title\n\nBody")
        stale = note.updated_at - timedelta(seconds=10)
        result = NotesSyncService.sync_operations(
            session,
            "user-1",
            {
                "last_sync": None,
                "operations": [
                    {
                        "operation_id": "op-1",
                        "op": "update",
                        "id": str(note.id),
                        "content": "Updated",
                        "client_updated_at": stale.isoformat(),
                    }
                ],
            },
        )
        assert result.conflicts
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()


def test_websites_sync_conflict(test_db_engine):
    connection, session, schema = _make_session(test_db_engine)
    try:
        website = WebsitesService.save_website(
            session,
            "user-1",
            url="https://example.com/sync",
            title="Sync",
            content="Content",
            source="https://example.com/sync",
        )
        stale = website.updated_at - timedelta(seconds=10)
        result = WebsitesSyncService.sync_operations(
            session,
            "user-1",
            {
                "operations": [
                    {
                        "operation_id": "op-2",
                        "op": "rename",
                        "id": str(website.id),
                        "title": "New Title",
                        "client_updated_at": stale.isoformat(),
                    }
                ]
            },
        )
        assert result.conflicts
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()


def test_files_sync_conflict(test_db_engine):
    connection, session, schema = _make_session(test_db_engine)
    try:
        file_record = FileIngestionService.create_ingestion(
            session,
            "user-1",
            filename_original="sync.txt",
            path="sync.txt",
            mime_original="text/plain",
            size_bytes=10,
        )[0]
        stale = file_record.updated_at - timedelta(seconds=10)
        result = FilesSyncService.sync_operations(
            session,
            "user-1",
            {
                "operations": [
                    {
                        "operation_id": "op-3",
                        "op": "rename",
                        "id": str(file_record.id),
                        "filename": "sync-renamed.txt",
                        "client_updated_at": stale.isoformat(),
                    }
                ]
            },
        )
        assert result.conflicts
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()
