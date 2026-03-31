"""Onboarding state API router."""
# ruff: noqa: B008

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.onboarding_service import OnboardingService

router = APIRouter(prefix="/onboarding", tags=["onboarding"])


class MilestonesPayload(BaseModel):
    """Milestone completion timestamps."""

    provider_connected: str | None = None
    first_outcome_completed: str | None = None
    profile_basics_set: str | None = None
    communication_style_set: str | None = None
    secondary_tour_seen: str | None = None


class PermissionsPayload(BaseModel):
    """Per-permission authorization state."""

    location: str = "not_asked"
    notifications: str = "not_asked"


class OnboardingStateResponse(BaseModel):
    """Response payload for onboarding state."""

    status: str
    provider_ready: bool
    current_onboarding_step: str
    is_onboarding_complete: bool
    intent: str | None
    milestones: MilestonesPayload
    permissions: PermissionsPayload
    last_prompted_at: str | None


class OnboardingUpdate(BaseModel):
    """Request payload for updating onboarding state."""

    model_config = ConfigDict(extra="forbid")

    status: str | None = None
    intent: str | None = None
    milestones: dict[str, str | None] | None = None
    permissions: dict[str, str] | None = None
    last_prompted_at: str | None = None


@router.get("", response_model=OnboardingStateResponse)
def get_onboarding(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Return the current onboarding state for the authenticated user.

    Args:
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Current onboarding state payload.
    """
    state = OnboardingService.get_onboarding_state(db, user_id)
    return OnboardingStateResponse(
        **{
            **state,
            "milestones": state["milestones"],
            "permissions": state["permissions"],
        }
    )


@router.patch("", response_model=OnboardingStateResponse)
def update_onboarding(
    payload: OnboardingUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Apply a partial update to the onboarding state for the authenticated user.

    Args:
        payload: Partial onboarding update.
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Updated onboarding state payload.
    """
    updates = payload.model_dump(exclude_unset=True)
    state = OnboardingService.update_onboarding_state(db, user_id, updates)
    return OnboardingStateResponse(
        **{
            **state,
            "milestones": state["milestones"],
            "permissions": state["permissions"],
        }
    )
