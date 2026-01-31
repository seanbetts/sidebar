"""Scratchpad router for the fixed scratchpad note."""
# ruff: noqa: B008

from fastapi import APIRouter, Depends
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from api.auth import bearer_scheme, verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError
from api.services.notes_service import NotesService

router = APIRouter(prefix="/scratchpad", tags=["scratchpad"])

SCRATCHPAD_TITLE = "✏️ Scratchpad"
SCRATCHPAD_HEADING = f"# {SCRATCHPAD_TITLE}"
SCRATCHPAD_DIVIDER = "\n\n___\n\n"


def ensure_title(content: str) -> str:
    """Ensure scratchpad content starts with the scratchpad H1 title.

    Args:
        content: Scratchpad content.

    Returns:
        Content with the scratchpad title prepended when missing.
    """
    trimmed = (content or "").lstrip()
    if trimmed.startswith(SCRATCHPAD_HEADING):
        return content
    return f"{SCRATCHPAD_HEADING}\n\n{content or ''}".strip() + "\n"


def strip_heading(content: str) -> str:
    """Strip the scratchpad heading from content if present."""
    if not content:
        return ""
    trimmed = content.lstrip()
    if not trimmed.startswith(SCRATCHPAD_HEADING):
        return content.strip("\n")
    lines = trimmed.splitlines()
    if not lines:
        return ""
    remaining = "\n".join(lines[1:]).lstrip("\n")
    return remaining.strip("\n")


def join_sections(sections: list[str]) -> str:
    """Join non-empty sections with the scratchpad divider."""
    parts = [
        section.strip("\n") for section in sections if section and section.strip("\n")
    ]
    if not parts:
        return ""
    return SCRATCHPAD_DIVIDER.join(parts)


def merge_content(existing: str, incoming: str, mode: str) -> str:
    """Merge scratchpad content using append/prepend/replace semantics."""
    existing_body = strip_heading(existing)
    incoming_body = strip_heading(incoming)
    if mode == "replace":
        merged = incoming_body
    elif mode == "prepend":
        merged = join_sections([incoming_body, existing_body])
    else:
        merged = join_sections([existing_body, incoming_body])
    return ensure_title(merged)


@router.get("")
def get_scratchpad(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch or create the scratchpad note.

    Args:
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Scratchpad note payload.
    """
    note = NotesService.get_note_by_title(
        db, user_id, SCRATCHPAD_TITLE, mark_opened=True
    )
    if not note:
        note = NotesService.create_note(
            db,
            user_id,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder="",
        )

    return {
        "id": str(note.id),
        "title": note.title,
        "content": note.content,
        "updated_at": note.updated_at.isoformat() if note.updated_at else None,
    }


@router.post("")
def update_scratchpad(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
):
    """Update scratchpad content.

    Args:
        request: Request payload with content.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        credentials: Parsed authorization header details.
        db: Database session.

    Returns:
        Update result payload.
    """
    content = request.get("content", "")
    mode_raw = request.get("mode")
    mode = (mode_raw or "").strip().lower()
    if mode and mode not in {"append", "prepend", "replace"}:
        raise BadRequestError("mode must be append, prepend, or replace")

    token = credentials.credentials if credentials else ""
    is_pat = token.startswith("sb_pat_")
    if not mode:
        mode = "prepend" if is_pat else "append"

    note = NotesService.get_note_by_title(
        db, user_id, SCRATCHPAD_TITLE, mark_opened=False
    )
    if not note:
        note = NotesService.create_note(
            db,
            user_id,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder="",
        )

    if mode_raw is None and not strip_heading(content):
        mode = "replace"
    merged_content = merge_content(note.content, content, mode)
    updated = NotesService.update_note(
        db, user_id, note.id, merged_content, title=SCRATCHPAD_TITLE
    )

    return {"success": True, "id": str(updated.id)}


@router.delete("")
def clear_scratchpad(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Clear the scratchpad content.

    Args:
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Clear result payload.
    """
    note = NotesService.get_note_by_title(
        db, user_id, SCRATCHPAD_TITLE, mark_opened=False
    )
    if not note:
        note = NotesService.create_note(
            db,
            user_id,
            content=f"# {SCRATCHPAD_TITLE}\n\n",
            title=SCRATCHPAD_TITLE,
            folder="",
        )
    else:
        NotesService.update_note(
            db, user_id, note.id, f"# {SCRATCHPAD_TITLE}\n\n", title=SCRATCHPAD_TITLE
        )

    return {"success": True, "id": str(note.id)}
