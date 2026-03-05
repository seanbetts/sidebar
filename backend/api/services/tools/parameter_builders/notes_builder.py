"""Parameter builders for notes tools."""

from __future__ import annotations

from api.services.notes_title import derive_note_title
from api.services.tools.parameter_builders.base import BaseParameterBuilder


class NotesParameterBuilder(BaseParameterBuilder):
    """Builders for notes and scratchpad tool arguments."""

    @staticmethod
    def derive_title_from_content(content: str) -> str:
        """Derive a note title from content."""
        return derive_note_title(content)

    @staticmethod
    def build_create_args(params: dict) -> list:
        """Build CLI arguments for notes create."""
        title = NotesParameterBuilder.derive_title_from_content(
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
        title = NotesParameterBuilder.derive_title_from_content(
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
    def build_archive_args(params: dict) -> list:
        """Build CLI arguments for notes archive/unarchive."""
        return [
            params["note_id"],
            "--archived",
            str(params["archived"]).lower(),
            "--database",
            "--user-id",
            params["user_id"],
        ]

    @staticmethod
    def build_download_args(params: dict) -> list:
        """Build CLI arguments for note download/export."""
        return [params["note_id"], "--database", "--user-id", params["user_id"]]

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
    def build_create_folder_args(params: dict) -> list:
        """Build CLI arguments for create folder."""
        return [params["path"], "--database", "--user-id", params["user_id"]]

    @staticmethod
    def build_rename_folder_args(params: dict) -> list:
        """Build CLI arguments for rename folder."""
        return [
            params["old_path"],
            "--new-name",
            params["new_name"],
            "--database",
            "--user-id",
            params["user_id"],
        ]

    @staticmethod
    def build_move_folder_args(params: dict) -> list:
        """Build CLI arguments for move folder."""
        args = [params["old_path"], "--database", "--user-id", params["user_id"]]
        if "new_parent" in params:
            args.extend(["--new-parent", params["new_parent"]])
        return args

    @staticmethod
    def build_delete_folder_args(params: dict) -> list:
        """Build CLI arguments for delete folder."""
        return [params["path"], "--database", "--user-id", params["user_id"]]

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
