"""Public auth-flow router."""
# ruff: noqa: B008

from fastapi import APIRouter, status
from pydantic import BaseModel, ConfigDict, EmailStr

from api.services.password_reset_service import PasswordResetService

router = APIRouter(prefix="/auth", tags=["auth"])


class PasswordResetRequestPayload(BaseModel):
    """Password reset request payload."""

    model_config = ConfigDict(extra="forbid")

    email: EmailStr


class PasswordResetRequestResponse(BaseModel):
    """Generic password reset acceptance response."""

    status: str


@router.post(
    "/password-reset/request",
    response_model=PasswordResetRequestResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def request_password_reset(payload: PasswordResetRequestPayload):
    """Start password reset delivery for an email address.

    The response intentionally does not reveal whether the email belongs to an
    account.
    """
    await PasswordResetService.request_password_reset(payload.email.strip())
    return PasswordResetRequestResponse(status="accepted")
