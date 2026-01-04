"""sideBar Skills API - FastAPI + MCP integration."""
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from fastmcp import FastMCP
from api.routers import health, chat, conversations, files, ingestion, websites, scratchpad, notes, settings as user_settings, places, skills, weather, memories, things
from api.mcp.tools import register_mcp_tools
from api.config import settings
from api.supabase_jwt import SupabaseJWTValidator, JWTValidationError
from api.models.user_settings import UserSettings
from sqlalchemy import text
from api.executors.skill_executor import SkillExecutor
from api.security.path_validator import PathValidator
from api.middleware.error_handler import (
    api_error_handler,
    http_exception_handler,
    unhandled_exception_handler,
)
from api.middleware.deprecation import DeprecationMiddleware
from api.exceptions import APIError
import logging

# Configure audit logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def _auth_error(status_code: int, code: str, message: str, headers: dict | None = None) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message, "details": {}}},
        headers=headers,
    )

# Create FastMCP server and get its HTTP app
mcp = FastMCP("sidebar-skills")
register_mcp_tools(mcp)
mcp_app = mcp.http_app()


# Combined lifespan that wraps MCP lifespan and our startup logic
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Combined lifespan for MCP and app state initialization."""
    # Use MCP's lifespan context
    async with mcp_app.lifespan(app):
        # Initialize our app state
        app.state.executor = SkillExecutor(
            skills_dir=settings.skills_dir,
            workspace_base=settings.workspace_base
        )
        app.state.path_validator = PathValidator(
            workspace_base=settings.workspace_base,
            writable_paths=settings.writable_paths
        )
        yield
        # Cleanup happens here if needed


# Create main FastAPI app with combined lifespan
app = FastAPI(
    title="sideBar Skills API",
    description="Skills API with FastAPI REST + MCP Streamable HTTP",
    version="1.0.0",
    lifespan=lifespan
)

# Register error handlers
app.add_exception_handler(APIError, api_error_handler)
app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)
app.add_middleware(DeprecationMiddleware)


# Unified authentication middleware
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Apply JWT auth to all endpoints except /api/health."""
    # Skip auth for health check
    if request.url.path == "/api/health":
        response = await call_next(request)
        return response

    if settings.auth_dev_mode:
        if not settings.allow_auth_dev_mode:
            logger.warning("AUTH_DEV_MODE is enabled outside local/test environment.")
            return _auth_error(403, "AUTH_DEV_MODE_FORBIDDEN", "AUTH_DEV_MODE requires APP_ENV=local")
        response = await call_next(request)
        return response

    # Allow Things bridge heartbeat or install with bridge token headers.
    if request.url.path in {"/api/things/bridges/heartbeat", "/api/things/bridges/install"}:
        bridge_id = request.headers.get("X-Bridge-Id")
        bridge_token = request.headers.get("X-Bridge-Token")
        if bridge_id and bridge_token:
            from api.db.session import SessionLocal
            from api.models.things_bridge import ThingsBridge
            with SessionLocal() as db:
                record = (
                    db.query(ThingsBridge)
                    .filter(
                        ThingsBridge.id == bridge_id,
                        ThingsBridge.bridge_token == bridge_token,
                    )
                    .first()
                )
            if record:
                request.state.user_id = record.user_id
                response = await call_next(request)
                return response
            return _auth_error(401, "INVALID_BRIDGE_TOKEN", "Invalid bridge token")
        if request.url.path == "/api/things/bridges/install" and request.headers.get("X-Install-Token"):
            response = await call_next(request)
            return response

    # Check for Authorization header
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        return _auth_error(
            401,
            "MISSING_AUTHORIZATION",
            "Missing Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Verify JWT token or Shortcuts PAT
    try:
        scheme, token = auth_header.split()
        if scheme.lower() != "bearer":
            raise ValueError("Invalid scheme")
        if token.startswith("sb_pat_"):
            from api.db.session import SessionLocal
            with SessionLocal() as db:
                db.execute(text("SET app.pat_token = :token"), {"token": token})
                record = (
                    db.query(UserSettings)
                    .filter(UserSettings.shortcuts_pat == token)
                    .first()
                )
            if not record:
                return _auth_error(
                    401,
                    "INVALID_API_TOKEN",
                    "Invalid API token",
                    headers={"WWW-Authenticate": "Bearer"},
                )
            request.state.user_id = record.user_id
        else:
            validator = SupabaseJWTValidator()
            payload = await validator.validate_token(token)
            request.state.user_id = payload.get("sub")
            if not request.state.user_id:
                raise JWTValidationError("Missing user ID")
    except (ValueError, AttributeError, JWTValidationError):
        return _auth_error(
            401,
            "INVALID_AUTHORIZATION",
            "Invalid Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    response = await call_next(request)
    return response


# Add REST routers BEFORE mounting MCP (auth handled by middleware)
app.include_router(health.router, prefix="/api/v1", tags=["health"])
app.include_router(chat.router, prefix="/api/v1", tags=["chat"])
app.include_router(conversations.router, prefix="/api/v1", tags=["conversations"])
app.include_router(files.router, prefix="/api/v1", tags=["files"])
app.include_router(ingestion.router, prefix="/api/v1", tags=["ingestion"])
app.include_router(notes.router, prefix="/api/v1", tags=["notes"])
app.include_router(websites.router, prefix="/api/v1", tags=["websites"])
app.include_router(scratchpad.router, prefix="/api/v1", tags=["scratchpad"])
app.include_router(user_settings.router, prefix="/api/v1", tags=["settings"])
app.include_router(memories.router, prefix="/api/v1", tags=["memories"])
app.include_router(places.router, prefix="/api/v1", tags=["places"])
app.include_router(skills.router, prefix="/api/v1", tags=["skills"])
app.include_router(weather.router, prefix="/api/v1", tags=["weather"])
app.include_router(things.router, prefix="/api/v1", tags=["things"])

# Legacy routes (deprecated)
app.include_router(health.router, prefix="/api", tags=["health-legacy"], deprecated=True)
app.include_router(chat.router, prefix="/api", tags=["chat-legacy"], deprecated=True)
app.include_router(conversations.router, prefix="/api", tags=["conversations-legacy"], deprecated=True)
app.include_router(files.router, prefix="/api", tags=["files-legacy"], deprecated=True)
app.include_router(ingestion.router, prefix="/api", tags=["ingestion-legacy"], deprecated=True)
app.include_router(notes.router, prefix="/api", tags=["notes-legacy"], deprecated=True)
app.include_router(websites.router, prefix="/api", tags=["websites-legacy"], deprecated=True)
app.include_router(scratchpad.router, prefix="/api", tags=["scratchpad-legacy"], deprecated=True)
app.include_router(user_settings.router, prefix="/api", tags=["settings-legacy"], deprecated=True)
app.include_router(memories.router, prefix="/api", tags=["memories-legacy"], deprecated=True)
app.include_router(places.router, prefix="/api", tags=["places-legacy"], deprecated=True)
app.include_router(skills.router, prefix="/api", tags=["skills-legacy"], deprecated=True)
app.include_router(weather.router, prefix="/api", tags=["weather-legacy"], deprecated=True)
app.include_router(things.router, prefix="/api", tags=["things-legacy"], deprecated=True)

# Mount MCP endpoint (auth handled by middleware)
# FastMCP creates its own /mcp route, so we mount at root
# This makes the MCP endpoint available at /mcp (not /mcp/mcp)
app.mount("", mcp_app)


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "message": "sideBar Skills API",
        "endpoints": {
            "rest": "/docs (Bearer token)",
            "mcp": "/mcp (Bearer token)",
            "chat": "/api/chat/stream (Bearer token, SSE)",
            "conversations": "/api/conversations (Bearer token)",
            "health": "/api/health (no auth)"
        },
        "security": {
            "auth": "Unified bearer token for all endpoints",
            "path_jailing": "All paths restricted to the configured storage root",
            "write_allowlist": settings.writable_paths
        }
    }
