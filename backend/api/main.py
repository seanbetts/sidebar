"""sideBar Skills API - FastAPI + MCP integration."""
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastmcp import FastMCP
from api.routers import health, chat, conversations, files, websites, scratchpad, notes, settings as user_settings, places, skills, weather, memories
from api.mcp.tools import register_mcp_tools
from api.config import settings
from api.executors.skill_executor import SkillExecutor
from api.security.path_validator import PathValidator
import logging

# Configure audit logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
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


# Unified authentication middleware
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Apply bearer token auth to all endpoints except /api/health."""
    # Skip auth for health check
    if request.url.path == "/api/health":
        response = await call_next(request)
        return response

    # Check for Authorization header
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        return JSONResponse(
            status_code=401,
            content={"error": "Missing Authorization header"},
            headers={"WWW-Authenticate": "Bearer"}
        )

    # Verify bearer token
    try:
        scheme, token = auth_header.split()
        if scheme.lower() != "bearer":
            raise ValueError("Invalid scheme")
        if token != settings.bearer_token:
            raise ValueError("Invalid token")
    except (ValueError, AttributeError):
        return JSONResponse(
            status_code=401,
            content={"error": "Invalid Authorization header"},
            headers={"WWW-Authenticate": "Bearer"}
        )

    response = await call_next(request)
    return response


# Add REST routers BEFORE mounting MCP (auth handled by middleware)
app.include_router(health.router, prefix="/api", tags=["health"])
app.include_router(chat.router, prefix="/api", tags=["chat"])
app.include_router(conversations.router, prefix="/api", tags=["conversations"])
app.include_router(files.router, prefix="/api", tags=["files"])
app.include_router(notes.router, prefix="/api", tags=["notes"])
app.include_router(websites.router, prefix="/api", tags=["websites"])
app.include_router(scratchpad.router, prefix="/api", tags=["scratchpad"])
app.include_router(user_settings.router, prefix="/api", tags=["settings"])
app.include_router(memories.router, prefix="/api", tags=["memories"])
app.include_router(places.router, prefix="/api", tags=["places"])
app.include_router(skills.router, prefix="/api", tags=["skills"])
app.include_router(weather.router, prefix="/api", tags=["weather"])

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
            "path_jailing": "All paths restricted to /workspace",
            "write_allowlist": settings.writable_paths
        }
    }
