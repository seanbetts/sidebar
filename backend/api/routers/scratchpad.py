"""Scratchpad router for the fixed scratchpad note."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from api.auth import verify_bearer_token
from api.db.session import get_db
from api.services.notes_service import NotesService

router = APIRouter(prefix="/scratchpad", tags=["scratchpad"])

SCRATCHPAD_TITLE = "✏️ Scratchpad"


def ensure_title(content: str) -> str:
    trimmed = (content or "").lstrip()
    if trimmed.startswith("#"):
        return content
    return f"# {SCRATCHPAD_TITLE}\n\n{content or ''}".strip() + "\n"


@router.get("")
async def get_scratchpad(
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    note = NotesService.get_note_by_title(db, SCRATCHPAD_TITLE, mark_opened=True)
    if not note:
        note = NotesService.create_note(
            db,
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
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    content = request.get("content", "")
    note = NotesService.get_note_by_title(db, SCRATCHPAD_TITLE, mark_opened=False)
    if not note:
        note = NotesService.create_note(
            db,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder=""
        )

    updated = NotesService.update_note(
        db,
        note.id,
        ensure_title(content),
        title=SCRATCHPAD_TITLE
    )

    return {"success": True, "id": str(updated.id)}


@router.delete("")
async def clear_scratchpad(
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    note = NotesService.get_note_by_title(db, SCRATCHPAD_TITLE, mark_opened=False)
    if not note:
        note = NotesService.create_note(
            db,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder=""
        )
    else:
        NotesService.update_note(
            db,
            note.id,
            f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE
        )

    return {"success": True, "id": str(note.id)}
