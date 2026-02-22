"""MCP tool definitions with semantic parameters (not CLI-style)."""

from fastmcp import FastMCP

from api.config import settings
from api.db.dependencies import get_tool_user_id
from api.mcp.fs_tools import register_fs_tools
from api.mcp.notes_tools import register_notes_tools
from api.security.path_validator import PathValidator
from api.services.agent.skills.executor import SkillExecutor


def register_mcp_tools(mcp: FastMCP) -> None:
    """Register all MCP tools with semantic parameters."""
    executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
    path_validator = PathValidator(settings.workspace_base, settings.writable_paths)
    default_user_id = get_tool_user_id()

    register_fs_tools(mcp, executor, path_validator, default_user_id)
    register_notes_tools(mcp, executor, default_user_id)
