"""Health check endpoint."""

import os

from fastapi import APIRouter, status
from fastapi.responses import JSONResponse

from api.config import settings

router = APIRouter()


def _missing_config() -> list[str]:
    missing: list[str] = []
    if not settings.supabase_url:
        missing.append("SUPABASE_URL")
    if not settings.supabase_anon_key:
        missing.append("SUPABASE_ANON_KEY")
    if not os.getenv("SUPABASE_PROJECT_ID"):
        missing.append("SUPABASE_PROJECT_ID")
    if not (os.getenv("SUPABASE_POSTGRES_PSWD") or os.getenv("SUPABASE_APP_PSWD")):
        missing.append("SUPABASE_POSTGRES_PSWD")
    use_pooler = os.getenv("SUPABASE_USE_POOLER", "true").lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    if use_pooler and not os.getenv("SUPABASE_POOLER_HOST"):
        missing.append("SUPABASE_POOLER_HOST")
    return missing


@router.get("/health")
async def health_check():
    """Health check endpoint (no auth required)."""
    missing = _missing_config()
    if missing:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "unhealthy",
                "missing": missing,
                "message": "Missing required configuration.",
            },
        )
    return {"status": "healthy"}
