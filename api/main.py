"""Agent Smith Skills API - FastAPI + MCP integration."""
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastmcp import FastMCP
from api.routers import health
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

# Create main FastAPI app
app = FastAPI(
    title="Agent Smith Skills API",
    description="Skills API with FastAPI REST + MCP Streamable HTTP",
    version="1.0.0"
)

# Create FastMCP server with Streamable HTTP
mcp = FastMCP("agent-smith-skills", stateless_http=True)
register_mcp_tools(mcp)


# Unified authentication middleware
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Apply bearer token auth to all endpoints except /health."""
    # Skip auth for health check
    if request.url.path == "/health":
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


# Mount MCP endpoint (auth handled by middleware)
# FastMCP with stateless_http=True exposes the app directly
app.mount("/mcp", mcp.app)

# Add REST routers (auth handled by middleware)
app.include_router(health.router, tags=["health"])


# Initialize executor and path validator as app state
@app.on_event("startup")
async def startup():
    """Initialize application state on startup."""
    app.state.executor = SkillExecutor(
        skills_dir=settings.skills_dir,
        workspace_base=settings.workspace_base
    )
    app.state.path_validator = PathValidator(
        workspace_base=settings.workspace_base,
        writable_paths=settings.writable_paths
    )


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "message": "Agent Smith Skills API",
        "endpoints": {
            "rest": "/docs (Bearer token)",
            "mcp": "/mcp (Bearer token)",
            "health": "/health (no auth)"
        },
        "security": {
            "auth": "Unified bearer token for all endpoints",
            "path_jailing": "All paths restricted to /workspace",
            "write_allowlist": settings.writable_paths
        }
    }
