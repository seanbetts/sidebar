"""Notes folder and ordering routes."""
# ruff: noqa: B008

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError
from api.services.notes_service import NotesService
from api.services.notes_workspace_service import NotesWorkspaceService
from api.utils.validation import parse_uuid

router = APIRouter()


@router.patch("/pinned-order")
def update_pinned_order(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update pinned order for notes."""
    order = request.get("order", [])
    if not isinstance(order, list):
        raise BadRequestError("order must be a list")
    note_ids: list[uuid.UUID] = []
    for item in order:
        note_ids.append(parse_uuid(item, "note", "id"))

    NotesService.update_pinned_order(db, user_id, note_ids)
    return {"success": True}


@router.post("/folders")
def create_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Create a notes folder."""
    path = (request.get("path") or "").strip("/")
    if not path:
        raise BadRequestError("path required")

    return NotesWorkspaceService.create_folder(db, user_id, path)


@router.patch("/folders/rename")
def rename_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Rename a notes folder."""
    old_path = (request.get("oldPath") or "").strip("/")
    new_name = (request.get("newName") or "").strip("/")
    if not old_path or not new_name:
        raise BadRequestError("oldPath and newName required")

    return NotesWorkspaceService.rename_folder(db, user_id, old_path, new_name)


@router.patch("/folders/move")
def move_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Move a notes folder to a new parent."""
    old_path = (request.get("oldPath") or "").strip("/")
    new_parent = (request.get("newParent") or "").strip("/")
    if not old_path:
        raise BadRequestError("oldPath required")

    try:
        return NotesWorkspaceService.move_folder(db, user_id, old_path, new_parent)
    except ValueError as exc:
        raise BadRequestError(str(exc)) from exc


@router.delete("/folders")
def delete_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Delete a notes folder."""
    path = (request.get("path") or "").strip("/")
    if not path:
        raise BadRequestError("path required")

    return NotesWorkspaceService.delete_folder(db, user_id, path)
