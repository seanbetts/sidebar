"""Build CLI arguments for tool execution."""

from __future__ import annotations

from api.services.tools.parameter_builders import (
    FsParameterBuilder,
    NotesParameterBuilder,
    SkillsParameterBuilder,
    TasksParameterBuilder,
    TranscriptionParameterBuilder,
    WebParameterBuilder,
    WebsiteParameterBuilder,
)


def derive_title_from_content(content: str) -> str:
    """Derive a note title from content."""
    return NotesParameterBuilder.derive_title_from_content(content)


def build_fs_list_args(params: dict) -> list:
    """Build CLI arguments for the fs list tool."""
    return FsParameterBuilder.build_list_args(params)


def build_fs_read_args(params: dict) -> list:
    """Build CLI arguments for the fs read tool."""
    return FsParameterBuilder.build_read_args(params)


def build_fs_write_args(params: dict) -> list:
    """Build CLI arguments for the fs write tool."""
    return FsParameterBuilder.build_write_args(params)


def build_fs_search_args(params: dict) -> list:
    """Build CLI arguments for the fs search tool."""
    return FsParameterBuilder.build_search_args(params)


def build_notes_create_args(params: dict) -> list:
    """Build CLI arguments for notes create."""
    return NotesParameterBuilder.build_create_args(params)


def build_notes_update_args(params: dict) -> list:
    """Build CLI arguments for notes update."""
    return NotesParameterBuilder.build_update_args(params)


def build_notes_delete_args(params: dict) -> list:
    """Build CLI arguments for notes delete."""
    return NotesParameterBuilder.build_delete_args(params)


def build_notes_pin_args(params: dict) -> list:
    """Build CLI arguments for notes pin/unpin."""
    return NotesParameterBuilder.build_pin_args(params)


def build_notes_move_args(params: dict) -> list:
    """Build CLI arguments for notes move."""
    return NotesParameterBuilder.build_move_args(params)


def build_notes_read_args(params: dict) -> list:
    """Build CLI arguments for notes read."""
    return NotesParameterBuilder.build_read_args(params)


def build_notes_list_args(params: dict) -> list:
    """Build CLI arguments for notes list."""
    return NotesParameterBuilder.build_list_args(params)


def build_scratchpad_get_args(params: dict) -> list:
    """Build CLI arguments for scratchpad get."""
    return NotesParameterBuilder.build_scratchpad_get_args(params)


def build_scratchpad_update_args(params: dict) -> list:
    """Build CLI arguments for scratchpad update."""
    return NotesParameterBuilder.build_scratchpad_update_args(params)


def build_scratchpad_clear_args(params: dict) -> list:
    """Build CLI arguments for scratchpad clear."""
    return NotesParameterBuilder.build_scratchpad_clear_args(params)


def build_website_save_args(params: dict) -> list:
    """Build CLI arguments for website save."""
    return WebsiteParameterBuilder.build_save_args(params)


def build_website_delete_args(params: dict) -> list:
    """Build CLI arguments for website delete."""
    return WebsiteParameterBuilder.build_delete_args(params)


def build_website_pin_args(params: dict) -> list:
    """Build CLI arguments for website pin/unpin."""
    return WebsiteParameterBuilder.build_pin_args(params)


def build_website_archive_args(params: dict) -> list:
    """Build CLI arguments for website archive/unarchive."""
    return WebsiteParameterBuilder.build_archive_args(params)


def build_website_read_args(params: dict) -> list:
    """Build CLI arguments for website read."""
    return WebsiteParameterBuilder.build_read_args(params)


def build_website_list_args(params: dict) -> list:
    """Build CLI arguments for website list."""
    return WebsiteParameterBuilder.build_list_args(params)


def build_audio_transcribe_args(params: dict) -> list:
    """Build CLI arguments for audio transcription."""
    return TranscriptionParameterBuilder.build_audio_transcribe_args(params)


def build_youtube_download_args(params: dict) -> list:
    """Build CLI arguments for YouTube download."""
    return TranscriptionParameterBuilder.build_youtube_download_args(params)


def build_youtube_transcribe_args(params: dict) -> list:
    """Build CLI arguments for YouTube transcription."""
    return TranscriptionParameterBuilder.build_youtube_transcribe_args(params)


def build_subdomain_discover_args(params: dict) -> list:
    """Build CLI arguments for subdomain discovery."""
    return WebParameterBuilder.build_subdomain_discover_args(params)


def build_crawler_policy_args(params: dict) -> list:
    """Build CLI arguments for crawler policy analysis."""
    return WebParameterBuilder.build_crawler_policy_args(params)


def build_skill_package_args(params: dict) -> list:
    """Build CLI arguments for skill packaging."""
    return SkillsParameterBuilder.build_skill_package_args(params)


def build_mcp_evaluation_args(params: dict) -> list:
    """Build CLI arguments for MCP evaluation runs."""
    return SkillsParameterBuilder.build_mcp_evaluation_args(params)


def build_tasks_list_args(params: dict) -> list:
    """Build CLI arguments for list tasks."""
    return TasksParameterBuilder.build_list_args(params)


def build_tasks_search_args(params: dict) -> list:
    """Build CLI arguments for search tasks."""
    return TasksParameterBuilder.build_search_args(params)


def build_tasks_create_args(params: dict) -> list:
    """Build CLI arguments for create task."""
    return TasksParameterBuilder.build_create_args(params)


def build_tasks_complete_args(params: dict) -> list:
    """Build CLI arguments for complete task."""
    return TasksParameterBuilder.build_complete_args(params)


def build_tasks_defer_args(params: dict) -> list:
    """Build CLI arguments for defer task."""
    return TasksParameterBuilder.build_defer_args(params)


def build_tasks_clear_due_args(params: dict) -> list:
    """Build CLI arguments for clear task due date."""
    return TasksParameterBuilder.build_clear_due_args(params)


def build_tasks_create_project_args(params: dict) -> list:
    """Build CLI arguments for create project."""
    return TasksParameterBuilder.build_create_project_args(params)


def build_tasks_create_group_args(params: dict) -> list:
    """Build CLI arguments for create group."""
    return TasksParameterBuilder.build_create_group_args(params)


def build_tasks_trash_args(params: dict) -> list:
    """Build CLI arguments for trash task."""
    return TasksParameterBuilder.build_trash_args(params)


def build_tasks_delete_project_args(params: dict) -> list:
    """Build CLI arguments for delete project."""
    return TasksParameterBuilder.build_delete_project_args(params)


def build_tasks_delete_group_args(params: dict) -> list:
    """Build CLI arguments for delete group."""
    return TasksParameterBuilder.build_delete_group_args(params)
