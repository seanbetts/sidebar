"""Notes router for database-backed note operations."""
# ruff: noqa: B008

from __future__ import annotations

import uuid

from fastapi import APIRouter, Body, Depends
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError, NoteNotFoundError, NotFoundError
from api.routers.notes_folders import router as notes_folders_router
from api.services.notes_helpers import note_sync_payload
from api.services.notes_service import NotesService
from api.services.notes_sync_service import NotesSyncService
from api.services.notes_workspace_service import NotesWorkspaceService
from api.utils.timestamps import parse_client_timestamp

router = APIRouter(prefix="/notes", tags=["notes"])
ARCHIVED_LIST_MAX_LIMIT = 500
router.include_router(notes_folders_router, tags=["notes"])


class NotesSearchRequest(BaseModel):
    """Search request payload for notes."""

    query: str
    limit: int = 50


@router.get("/tree")
def list_notes_tree(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return the hierarchical notes tree for the current user.

    Args:
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Tree structure of folders and notes.
    """
    tree = NotesWorkspaceService.list_tree(db, user_id, include_archived=False)
    summary = NotesService.archived_summary(db, user_id)
    return {**tree, **summary}


@router.get("/archived")
def list_archived_tree(
    limit: int = 200,
    offset: int = 0,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return the archived notes tree for the current user."""
    limit = max(1, min(limit, ARCHIVED_LIST_MAX_LIMIT))
    offset = max(0, offset)
    return NotesWorkspaceService.list_archived_tree(
        db,
        user_id,
        limit=limit,
        offset=offset,
    )


@router.post("/search")
def search_notes(
    query: str | None = None,
    limit: int = 50,
    request: NotesSearchRequest | None = Body(default=None),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Search notes by content and metadata.

    Args:
        query: Search query string.
        limit: Max results to return. Defaults to 50.
        request: Optional request payload with query and limit.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        List of matching notes.

    Raises:
        BadRequestError: If query is missing.
    """
    if request is not None:
        query = request.query
        limit = request.limit
    if not query:
        raise BadRequestError("query required")

    return NotesWorkspaceService.search(db, user_id, query, limit=limit)


@router.get("/{note_id}")
def get_note(
    note_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch a note by ID.

    Args:
        note_id: Note UUID.
        request: Optional payload with client_updated_at.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Note record and content.

    Raises:
        BadRequestError: For invalid ID.
        NotFoundError: If not found.
    """
    try:
        return NotesWorkspaceService.get_note(db, user_id, str(note_id))
    except ValueError as exc:
        raise BadRequestError(str(exc)) from exc
    except NoteNotFoundError as exc:
        raise NotFoundError("Note", str(note_id)) from exc


@router.post("")
def create_note(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Create a new note.

    Args:
        request: Request payload with content and optional path/folder.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Created note record.

    Raises:
        BadRequestError: If content is missing.
    """
    content = request.get("content")
    title = request.get("title") or None
    path = request.get("path", "")
    folder = (request.get("folder") or "").strip("/")
    client_id = request.get("client_id") or request.get("clientId")

    if content is None:
        raise BadRequestError("content required")

    return NotesWorkspaceService.create_note(
        db,
        user_id,
        content,
        title=title,
        path=path,
        folder=folder,
        client_id=client_id,
    )


@router.patch("/{note_id}/rename")
def rename_note(
    note_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Rename a note.

    Args:
        note_id: Note UUID.
        request: Request payload with newName.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Rename result.

    Raises:
        BadRequestError: For invalid request.
        NotFoundError: If not found.
    """
    new_name = request.get("newName", "")
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    if not new_name:
        raise BadRequestError("newName required")

    try:
        return NotesWorkspaceService.rename_note(
            db,
            user_id,
            str(note_id),
            new_name,
            client_updated_at=client_updated_at,
        )
    except ValueError as exc:
        raise BadRequestError(str(exc)) from exc
    except NoteNotFoundError as exc:
        raise NotFoundError("Note", str(note_id)) from exc


@router.delete("/{note_id}")
def delete_note(
    note_id: uuid.UUID,
    request: dict | None = Body(default=None),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Delete a note by ID.

    Args:
        note_id: Note UUID.
        request: Optional payload with client_updated_at.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        BadRequestError: For invalid ID.
        NotFoundError: If not found.
    """
    note = NotesService.get_note(db, user_id, note_id, mark_opened=False)
    if not note:
        raise NotFoundError("Note", str(note_id))
    payload = request or {}
    client_updated_at = parse_client_timestamp(
        payload.get("client_updated_at") or payload.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    deleted = NotesService.delete_note(
        db,
        user_id,
        note_id,
        client_updated_at=client_updated_at,
    )
    if not deleted:
        raise NotFoundError("Note", str(note_id))
    return NotesWorkspaceService.build_note_payload(note, include_content=True)


@router.post("/sync")
def sync_notes(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Apply offline note operations and return updates since last sync."""
    result = NotesSyncService.sync_operations(db, user_id, request)
    return {
        "applied": result.applied_ids,
        "notes": [
            NotesWorkspaceService.build_note_payload(note, include_content=True)
            for note in result.notes
        ],
        "conflicts": result.conflicts,
        "updates": {
            "notes": [note_sync_payload(note) for note in result.updated_notes],
        },
        "serverUpdatedSince": result.server_updated_since.isoformat()
        if result.server_updated_since
        else None,
    }


@router.get("/{note_id}/download")
def download_note(
    note_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Download a note as a markdown attachment.

    Args:
        note_id: Note UUID.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Markdown response with attachment headers.

    Raises:
        BadRequestError: For invalid ID.
        NotFoundError: If not found.
    """
    try:
        result = NotesWorkspaceService.download_note(db, user_id, str(note_id))
    except ValueError as exc:
        raise BadRequestError(str(exc)) from exc
    except NoteNotFoundError as exc:
        raise NotFoundError("Note", str(note_id)) from exc

    headers = {"Content-Disposition": f'attachment; filename="{result["filename"]}"'}
    return Response(result["content"], media_type="text/markdown", headers=headers)


@router.patch("/{note_id}/pin")
def update_pin(
    note_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Pin or unpin a note.

    Args:
        note_id: Note UUID.
        request: Request payload with pinned.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        BadRequestError: For invalid ID.
        NotFoundError: If not found.
    """
    pinned = bool(request.get("pinned", False))
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    try:
        note = NotesService.update_pinned(
            db,
            user_id,
            note_id,
            pinned,
            client_updated_at=client_updated_at,
        )
    except NoteNotFoundError as exc:
        raise NotFoundError("Note", str(note_id)) from exc
    return NotesWorkspaceService.build_note_payload(note, include_content=True)


@router.patch("/{note_id}")
def update_note(
    note_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update a note's content.

    Args:
        note_id: Note UUID.
        request: Request payload with content.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Updated note record.

    Raises:
        BadRequestError: For invalid request.
        NotFoundError: If not found.
    """
    content = request.get("content")
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    if content is None:
        raise BadRequestError("content required")

    try:
        return NotesWorkspaceService.update_note(
            db,
            user_id,
            str(note_id),
            content,
            client_updated_at=client_updated_at,
        )
    except ValueError as exc:
        raise BadRequestError(str(exc)) from exc
    except NoteNotFoundError as exc:
        raise NotFoundError("Note", str(note_id)) from exc


@router.patch("/{note_id}/move")
def update_folder(
    note_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Move a note to a different folder.

    Args:
        note_id: Note UUID.
        request: Request payload with folder.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        BadRequestError: For invalid ID.
        NotFoundError: If not found.
    """
    folder = request.get("folder", "") or ""
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    try:
        note = NotesService.update_folder(
            db,
            user_id,
            note_id,
            folder,
            client_updated_at=client_updated_at,
            op="archive",
        )
    except NoteNotFoundError as exc:
        raise NotFoundError("Note", str(note_id)) from exc
    return NotesWorkspaceService.build_note_payload(note, include_content=True)


@router.patch("/{note_id}/archive")
def update_archive(
    note_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Archive or unarchive a note.

    Args:
        note_id: Note UUID.
        request: Request payload with archived.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        BadRequestError: For invalid ID.
        NotFoundError: If not found.
    """
    archived = bool(request.get("archived", False))
    folder = "Archive" if archived else ""
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    try:
        note = NotesService.update_folder(
            db,
            user_id,
            note_id,
            folder,
            client_updated_at=client_updated_at,
        )
    except NoteNotFoundError as exc:
        raise NotFoundError("Note", str(note_id)) from exc
    return NotesWorkspaceService.build_note_payload(note, include_content=True)
