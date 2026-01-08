"""Parameter builders for filesystem tools."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class FsParameterBuilder(BaseParameterBuilder):
    """Builders for filesystem tool arguments."""

    @staticmethod
    def build_list_args(params: dict) -> list:
        """Build CLI arguments for the fs list tool."""
        path = params.get("path", ".")
        pattern = params.get("pattern", "*")
        recursive = params.get("recursive", False)

        args = [path, "--pattern", pattern]
        if recursive:
            args.append("--recursive")
        return FsParameterBuilder.append_user_id(args, params)

    @staticmethod
    def build_read_args(params: dict) -> list:
        """Build CLI arguments for the fs read tool."""
        args = [params["path"]]
        if "start_line" in params:
            args.extend(["--start-line", str(params["start_line"])])
        if "end_line" in params:
            args.extend(["--end-line", str(params["end_line"])])
        return FsParameterBuilder.append_user_id(args, params)

    @staticmethod
    def build_write_args(params: dict) -> list:
        """Build CLI arguments for the fs write tool."""
        args = [params["path"], "--content", params["content"]]
        if params.get("dry_run"):
            args.append("--dry-run")
        return FsParameterBuilder.append_user_id(args, params)

    @staticmethod
    def build_search_args(params: dict) -> list:
        """Build CLI arguments for the fs search tool."""
        directory = params.get("directory", ".")
        name_pattern = params.get("name_pattern")
        content_pattern = params.get("content_pattern")
        case_sensitive = params.get("case_sensitive", False)

        args = ["--directory", directory]
        if name_pattern:
            args.extend(["--name", name_pattern])
        if content_pattern:
            args.extend(["--content", content_pattern])
        if case_sensitive:
            args.append("--case-sensitive")
        return FsParameterBuilder.append_user_id(args, params)
