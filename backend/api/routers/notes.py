"""Notes router for database-backed note operations."""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy import or_
from sqlalchemy.orm import Session, load_only

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.models.note import Note
from api.services.notes_service import NotesService, NoteNotFoundError

router = APIRouter(prefix="/notes", tags=["notes"])


def require_note_id(value: str):
    note_id = NotesService.parse_note_id(value)
    if not note_id:
        raise HTTPException(status_code=400, detail="Invalid note id")
    return note_id


@router.get("/tree")
async def list_notes_tree(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    notes = (
        db.query(Note)
        .options(load_only(Note.id, Note.title, Note.metadata_, Note.updated_at))
        .filter(Note.user_id == user_id, Note.deleted_at.is_(None))
        .order_by(Note.updated_at.desc())
        .all()
    )
    tree = NotesService.build_notes_tree(notes)
    return {"children": tree.get("children", [])}


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

    notes = (
        db.query(Note)
        .filter(
            Note.user_id == user_id,
            Note.deleted_at.is_(None),
            or_(
                Note.title.ilike(f"%{query}%"),
                Note.content.ilike(f"%{query}%"),
            ),
        )
        .order_by(Note.updated_at.desc())
        .limit(limit)
        .all()
    )

    items = []
    for note in notes:
        metadata = note.metadata_ or {}
        folder = metadata.get("folder") or ""
        items.append({
            "name": f"{note.title}.md",
            "path": str(note.id),
            "type": "file",
            "modified": note.updated_at.timestamp() if note.updated_at else None,
            "pinned": bool(metadata.get("pinned")),
            "archived": NotesService.is_archived_folder(folder)
        })

    return {"items": items}


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

    notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
    for note in notes:
        note_folder = (note.metadata_ or {}).get("folder") or ""
        if note_folder == path or note_folder.startswith(f"{path}/"):
            return {"success": True, "exists": True}

    now = datetime.now(timezone.utc)
    note = Note(
        user_id=user_id,
        title="__folder__",
        content="",
        metadata_={"folder": path, "pinned": False, "folder_marker": True},
        created_at=now,
        updated_at=now,
        last_opened_at=None,
        deleted_at=None
    )
    db.add(note)
    db.commit()
    return {"success": True, "id": str(note.id)}


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

    parent = "/".join(old_path.split("/")[:-1])
    new_folder = f"{parent}/{new_name}".strip("/") if parent else new_name

    notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
    for note in notes:
        folder = (note.metadata_ or {}).get("folder") or ""
        if folder == old_path or folder.startswith(f"{old_path}/"):
            updated_folder = folder.replace(old_path, new_folder, 1)
            note.metadata_ = {**(note.metadata_ or {}), "folder": updated_folder}
            note.updated_at = datetime.now(timezone.utc)
    db.commit()
    return {"success": True, "newPath": f"folder:{new_folder}"}


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

    if new_parent and (new_parent == old_path or new_parent.startswith(f"{old_path}/")):
        raise HTTPException(status_code=400, detail="Invalid destination folder")

    basename = old_path.split("/")[-1]
    new_folder = f"{new_parent}/{basename}".strip("/") if new_parent else basename

    notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
    for note in notes:
        folder = (note.metadata_ or {}).get("folder") or ""
        if folder == old_path or folder.startswith(f"{old_path}/"):
            updated_folder = folder.replace(old_path, new_folder, 1)
            note.metadata_ = {**(note.metadata_ or {}), "folder": updated_folder}
            note.updated_at = datetime.now(timezone.utc)
    db.commit()
    return {"success": True, "newPath": f"folder:{new_folder}"}


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

    notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
    now = datetime.now(timezone.utc)
    for note in notes:
        note_folder = (note.metadata_ or {}).get("folder") or ""
        if note_folder == path or note_folder.startswith(f"{path}/"):
            note.deleted_at = now
            note.updated_at = now
    db.commit()
    return {"success": True}


@router.get("/{note_id}")
async def get_note(
    note_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    note_uuid = require_note_id(note_id)
    note = (
        db.query(Note)
        .filter(Note.user_id == user_id, Note.id == note_uuid, Note.deleted_at.is_(None))
        .first()
    )
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")

    content = note.content
    title = note.title
    modified = note.updated_at.timestamp() if note.updated_at else None
    note.last_opened_at = datetime.now(timezone.utc)
    db.commit()
    return {
        "content": content,
        "name": f"{title}.md",
        "path": str(note.id),
        "modified": modified
    }


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

    resolved_folder = folder
    if not resolved_folder and path:
        folder_path = Path(path).parent.as_posix()
        resolved_folder = "" if folder_path == "." else folder_path

    created = NotesService.create_note(db, user_id, content, folder=resolved_folder)
    return {"success": True, "modified": created.updated_at.timestamp(), "id": str(created.id)}


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

    note_uuid = require_note_id(note_id)
    try:
        updated = NotesService.update_note(db, user_id, note_uuid, content)
    except NoteNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")

    return {"success": True, "modified": updated.updated_at.timestamp(), "id": str(updated.id)}


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

    note_uuid = require_note_id(note_id)
    note = (
        db.query(Note)
        .filter(Note.user_id == user_id, Note.id == note_uuid, Note.deleted_at.is_(None))
        .first()
    )
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")

    title = Path(new_name).stem
    note.title = title
    note.content = NotesService.update_content_title(note.content, title)
    note.updated_at = datetime.now(timezone.utc)
    db.commit()
    return {"success": True, "newPath": str(note.id)}


@router.delete("/{note_id}")
async def delete_note(
    note_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    note_uuid = require_note_id(note_id)
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
    note_uuid = require_note_id(note_id)
    note = (
        db.query(Note)
        .filter(Note.user_id == user_id, Note.id == note_uuid, Note.deleted_at.is_(None))
        .first()
    )
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")

    filename = f"{note.title}.md"
    headers = {"Content-Disposition": f'attachment; filename="{filename}"'}
    return Response(note.content or "", media_type="text/markdown", headers=headers)


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
