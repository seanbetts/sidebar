"""User settings API router."""
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.user_settings_service import UserSettingsService


router = APIRouter(prefix="/settings", tags=["settings"])


class SettingsResponse(BaseModel):
    user_id: str
    communication_style: Optional[str] = None
    working_relationship: Optional[str] = None
    name: Optional[str] = None
    job_title: Optional[str] = None
    employer: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    pronouns: Optional[str] = None
    location: Optional[str] = None


class SettingsUpdate(BaseModel):
    communication_style: Optional[str] = None
    working_relationship: Optional[str] = None
    name: Optional[str] = None
    job_title: Optional[str] = None
    employer: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    pronouns: Optional[str] = None
    location: Optional[str] = None


DEFAULT_COMMUNICATION_STYLE = """Use UK English.

Be concise and direct.

Always use markdown formatting in your response

Never use em dashes.

Follow explicit user constraints strictly (for example, if asked for two sentences, produce exactly two sentences).

Default to a casual, colleague style.

Use minimal formatting by default. Prefer prose and paragraphs over headings and lists.

Avoid bullet points and numbered lists unless I explicitly ask for a list or the response is genuinely complex.

Do not use emojis unless I use one immediately before."""

DEFAULT_WORKING_RELATIONSHIP = """Challenge my assumptions constructively when useful.

Help with brainstorming questions, simplifying complex topics, and polishing prose.

Critique drafts and use Socratic dialogue to surface blind spots.

Any non obvious claim, statistic, or figure must be backed by an authentic published source. Never fabricate citations. If you cannot source it, say you do not know."""


def _resolve_default(value: Optional[str], default: str) -> Optional[str]:
    if value is None:
        return default
    trimmed = value.strip()
    return trimmed if trimmed else default


@router.get("", response_model=SettingsResponse)
async def get_settings(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    settings = UserSettingsService.get_settings(db, user_id)
    return SettingsResponse(
        user_id=user_id,
        communication_style=_resolve_default(
            settings.communication_style if settings else None,
            DEFAULT_COMMUNICATION_STYLE,
        ),
        working_relationship=_resolve_default(
            settings.working_relationship if settings else None,
            DEFAULT_WORKING_RELATIONSHIP,
        ),
        name=settings.name if settings else None,
        job_title=settings.job_title if settings else None,
        employer=settings.employer if settings else None,
        date_of_birth=settings.date_of_birth if settings else None,
        gender=settings.gender if settings else None,
        pronouns=settings.pronouns if settings else None,
        location=settings.location if settings else None,
    )


@router.patch("", response_model=SettingsResponse)
async def update_settings(
    payload: SettingsUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    updates = payload.dict(exclude_unset=True)
    settings = UserSettingsService.upsert_settings(
        db,
        user_id,
        **updates,
    )
    return SettingsResponse(
        user_id=user_id,
        communication_style=_resolve_default(
            settings.communication_style,
            DEFAULT_COMMUNICATION_STYLE,
        ),
        working_relationship=_resolve_default(
            settings.working_relationship,
            DEFAULT_WORKING_RELATIONSHIP,
        ),
        name=settings.name,
        job_title=settings.job_title,
        employer=settings.employer,
        date_of_birth=settings.date_of_birth,
        gender=settings.gender,
        pronouns=settings.pronouns,
        location=settings.location,
    )
