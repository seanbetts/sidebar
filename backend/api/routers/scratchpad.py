"""Scratchpad router for the fixed scratchpad note."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.notes_service import NotesService

router = APIRouter(prefix="/scratchpad", tags=["scratchpad"])

SCRATCHPAD_TITLE = "✏️ Scratchpad"


def ensure_title(content: str) -> str:
    """Ensure scratchpad content starts with the scratchpad H1 title.

    Args:
        content: Scratchpad content.

    Returns:
        Content with the scratchpad title prepended when missing.
    """
    trimmed = (content or "").lstrip()
    if trimmed.startswith("#"):
        return content
    return f"# {SCRATCHPAD_TITLE}\n\n{content or ''}".strip() + "\n"


@router.get("")
async def get_scratchpad(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Fetch or create the scratchpad note.

    Args:
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Scratchpad note payload.
    """
    note = NotesService.get_note_by_title(db, user_id, SCRATCHPAD_TITLE, mark_opened=True)
    if not note:
        note = NotesService.create_note(
            db,
            user_id,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder=""
        )

    return {
        "id": str(note.id),
        "title": note.title,
        "content": note.content,
        "updated_at": note.updated_at.isoformat() if note.updated_at else None
    }


@router.post("")
async def update_scratchpad(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Update scratchpad content.

    Args:
        request: Request payload with content.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Update result payload.
    """
    content = request.get("content", "")
    note = NotesService.get_note_by_title(db, user_id, SCRATCHPAD_TITLE, mark_opened=False)
    if not note:
        note = NotesService.create_note(
            db,
            user_id,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder=""
        )

    updated = NotesService.update_note(
        db,
        user_id,
        note.id,
        ensure_title(content),
        title=SCRATCHPAD_TITLE
    )

    return {"success": True, "id": str(updated.id)}


@router.delete("")
async def clear_scratchpad(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Clear the scratchpad content.

    Args:
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Clear result payload.
    """
    note = NotesService.get_note_by_title(db, user_id, SCRATCHPAD_TITLE, mark_opened=False)
    if not note:
        note = NotesService.create_note(
            db,
            user_id,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder=""
        )
    else:
        NotesService.update_note(
            db,
            user_id,
            note.id,
            f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE
        )

    return {"success": True, "id": str(note.id)}
