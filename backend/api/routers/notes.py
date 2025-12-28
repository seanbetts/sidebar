"""Notes router for database-backed note operations."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.notes_service import NotesService, NoteNotFoundError
from api.services.notes_workspace_service import NotesWorkspaceService

router = APIRouter(prefix="/notes", tags=["notes"])


@router.get("/tree")
async def list_notes_tree(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    return NotesWorkspaceService.list_tree(db, user_id)


@router.post("/search")
async def search_notes(
    query: str,
    limit: int = 50,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    if not query:
        raise HTTPException(status_code=400, detail="query required")

    return NotesWorkspaceService.search(db, user_id, query, limit=limit)


@router.post("/folders")
async def create_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    path = (request.get("path") or "").strip("/")
    if not path:
        raise HTTPException(status_code=400, detail="path required")

    return NotesWorkspaceService.create_folder(db, user_id, path)


@router.patch("/folders/rename")
async def rename_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    old_path = (request.get("oldPath") or "").strip("/")
    new_name = (request.get("newName") or "").strip("/")
    if not old_path or not new_name:
        raise HTTPException(status_code=400, detail="oldPath and newName required")

    return NotesWorkspaceService.rename_folder(db, user_id, old_path, new_name)


@router.patch("/folders/move")
async def move_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    old_path = (request.get("oldPath") or "").strip("/")
    new_parent = (request.get("newParent") or "").strip("/")
    if not old_path:
        raise HTTPException(status_code=400, detail="oldPath required")

    try:
        return NotesWorkspaceService.move_folder(db, user_id, old_path, new_parent)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.delete("/folders")
async def delete_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    path = (request.get("path") or "").strip("/")
    if not path:
        raise HTTPException(status_code=400, detail="path required")

    return NotesWorkspaceService.delete_folder(db, user_id, path)


@router.get("/{note_id}")
async def get_note(
    note_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    try:
        return NotesWorkspaceService.get_note(db, user_id, note_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")


@router.post("")
async def create_note(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    content = request.get("content")
    path = request.get("path", "")
    folder = (request.get("folder") or "").strip("/")

    if content is None:
        raise HTTPException(status_code=400, detail="content required")

    return NotesWorkspaceService.create_note(db, user_id, content, path=path, folder=folder)


@router.patch("/{note_id}")
async def update_note(
    note_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    content = request.get("content")
    if content is None:
        raise HTTPException(status_code=400, detail="content required")

    try:
        return NotesWorkspaceService.update_note(db, user_id, note_id, content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")


@router.patch("/{note_id}/rename")
async def rename_note(
    note_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    new_name = request.get("newName", "")
    if not new_name:
        raise HTTPException(status_code=400, detail="newName required")

    try:
        return NotesWorkspaceService.rename_note(db, user_id, note_id, new_name)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")


@router.delete("/{note_id}")
async def delete_note(
    note_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    note_uuid = NotesService.parse_note_id(note_id)
    if not note_uuid:
        raise HTTPException(status_code=400, detail="Invalid note id")
    deleted = NotesService.delete_note(db, user_id, note_uuid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"success": True}


@router.get("/{note_id}/download")
async def download_note(
    note_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    try:
        result = NotesWorkspaceService.download_note(db, user_id, note_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")

    headers = {"Content-Disposition": f'attachment; filename="{result["filename"]}"'}
    return Response(result["content"], media_type="text/markdown", headers=headers)


@router.patch("/{note_id}/pin")
async def update_pin(
    note_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    pinned = bool(request.get("pinned", False))
    try:
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise HTTPException(status_code=400, detail="Invalid note id")
        NotesService.update_pinned(db, user_id, note_uuid, pinned)
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"success": True}


@router.patch("/{note_id}/move")
async def update_folder(
    note_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    folder = request.get("folder", "") or ""
    try:
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise HTTPException(status_code=400, detail="Invalid note id")
        NotesService.update_folder(db, user_id, note_uuid, folder)
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"success": True}


@router.patch("/{note_id}/archive")
async def update_archive(
    note_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    archived = bool(request.get("archived", False))
    folder = "Archive" if archived else ""
    try:
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise HTTPException(status_code=400, detail="Invalid note id")
        NotesService.update_folder(db, user_id, note_uuid, folder)
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"success": True}
