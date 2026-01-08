"""MCP tool definitions with semantic parameters (not CLI-style)."""

from fastmcp import FastMCP

from api.config import settings
from api.db.dependencies import DEFAULT_USER_ID
from api.executors.skill_executor import SkillExecutor
from api.mcp.fs_tools import register_fs_tools
from api.mcp.notes_tools import register_notes_tools
from api.security.path_validator import PathValidator


def register_mcp_tools(mcp: FastMCP) -> None:
    """Register all MCP tools with semantic parameters."""
    executor = SkillExecutor(settings.skills_dir, settings.workspace_base)
    path_validator = PathValidator(settings.workspace_base, settings.writable_paths)

    register_fs_tools(mcp, executor, path_validator, DEFAULT_USER_ID)
    register_notes_tools(mcp, executor, DEFAULT_USER_ID)
