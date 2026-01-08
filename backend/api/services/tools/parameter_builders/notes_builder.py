"""Parameter builders for notes tools."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class NotesParameterBuilder(BaseParameterBuilder):
    """Builders for notes and scratchpad tool arguments."""

    @staticmethod
    def derive_title_from_content(content: str) -> str:
        """Derive a note title from content.

        Args:
            content: Markdown or plain text.

        Returns:
            A non-empty title capped at 120 characters.
        """
        if not isinstance(content, str):
            return "Untitled Note"
        for line in content.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped[:120]
        return "Untitled Note"

    @staticmethod
    def build_create_args(params: dict) -> list:
        """Build CLI arguments for notes create."""
        title = params.get("title") or NotesParameterBuilder.derive_title_from_content(
            params.get("content", "")
        )
        args = [
            title,
            "--content",
            params["content"],
            "--mode",
            "create",
            "--database",
        ]
        NotesParameterBuilder.append_user_id(args, params)
        if "folder" in params:
            args.extend(["--folder", params["folder"]])
        if "tags" in params:
            args.extend(["--tags", ",".join(params["tags"])])
        return args

    @staticmethod
    def build_update_args(params: dict) -> list:
        """Build CLI arguments for notes update."""
        title = params.get("title") or NotesParameterBuilder.derive_title_from_content(
            params.get("content", "")
        )
        args = [
            title,
            "--content",
            params["content"],
            "--mode",
            "update",
            "--note-id",
            params["note_id"],
            "--database",
        ]
        NotesParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_delete_args(params: dict) -> list:
        """Build CLI arguments for notes delete."""
        return [params["note_id"], "--database", "--user-id", params["user_id"]]

    @staticmethod
    def build_pin_args(params: dict) -> list:
        """Build CLI arguments for notes pin/unpin."""
        return [
            params["note_id"],
            "--pinned",
            str(params["pinned"]).lower(),
            "--database",
            "--user-id",
            params["user_id"],
        ]

    @staticmethod
    def build_move_args(params: dict) -> list:
        """Build CLI arguments for notes move."""
        return [
            params["note_id"],
            "--folder",
            params["folder"],
            "--database",
            "--user-id",
            params["user_id"],
        ]

    @staticmethod
    def build_read_args(params: dict) -> list:
        """Build CLI arguments for notes read."""
        return [params["note_id"], "--database", "--user-id", params["user_id"]]

    @staticmethod
    def build_list_args(params: dict) -> list:
        """Build CLI arguments for notes list."""
        args = ["--database"]
        NotesParameterBuilder.append_user_id(args, params)
        for key, flag in [
            ("folder", "--folder"),
            ("pinned", "--pinned"),
            ("archived", "--archived"),
            ("created_after", "--created-after"),
            ("created_before", "--created-before"),
            ("updated_after", "--updated-after"),
            ("updated_before", "--updated-before"),
            ("opened_after", "--opened-after"),
            ("opened_before", "--opened-before"),
            ("title", "--title"),
        ]:
            value = params.get(key)
            if value is not None:
                args.extend([flag, str(value)])
        return args

    @staticmethod
    def build_scratchpad_get_args(params: dict) -> list:
        """Build CLI arguments for scratchpad get."""
        return ["--database", "--user-id", params["user_id"]]

    @staticmethod
    def build_scratchpad_update_args(params: dict) -> list:
        """Build CLI arguments for scratchpad update."""
        return [
            "--content",
            params["content"],
            "--database",
            "--user-id",
            params["user_id"],
        ]

    @staticmethod
    def build_scratchpad_clear_args(params: dict) -> list:
        """Build CLI arguments for scratchpad clear."""
        return ["--database", "--user-id", params["user_id"]]
