"""Parameter builders for website tools."""
from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class WebsiteParameterBuilder(BaseParameterBuilder):
    """Builders for website tool arguments."""

    @staticmethod
    def build_save_args(params: dict) -> list:
        """Build CLI arguments for website save."""
        return [params["url"], "--database", "--user-id", params["user_id"]]

    @staticmethod
    def build_delete_args(params: dict) -> list:
        """Build CLI arguments for website delete."""
        return [params["website_id"], "--database", "--user-id", params["user_id"]]

    @staticmethod
    def build_pin_args(params: dict) -> list:
        """Build CLI arguments for website pin/unpin."""
        return [
            params["website_id"],
            "--pinned",
            str(params["pinned"]).lower(),
            "--database",
            "--user-id",
            params["user_id"],
        ]

    @staticmethod
    def build_archive_args(params: dict) -> list:
        """Build CLI arguments for website archive/unarchive."""
        return [
            params["website_id"],
            "--archived",
            str(params["archived"]).lower(),
            "--database",
            "--user-id",
            params["user_id"],
        ]

    @staticmethod
    def build_read_args(params: dict) -> list:
        """Build CLI arguments for website read."""
        return [params["website_id"], "--database", "--user-id", params["user_id"]]

    @staticmethod
    def build_list_args(params: dict) -> list:
        """Build CLI arguments for website list."""
        args = ["--database"]
        WebsiteParameterBuilder.append_user_id(args, params)
        for key, flag in [
            ("domain", "--domain"),
            ("pinned", "--pinned"),
            ("archived", "--archived"),
            ("created_after", "--created-after"),
            ("created_before", "--created-before"),
            ("updated_after", "--updated-after"),
            ("updated_before", "--updated-before"),
            ("opened_after", "--opened-after"),
            ("opened_before", "--opened-before"),
            ("published_after", "--published-after"),
            ("published_before", "--published-before"),
            ("title", "--title"),
        ]:
            value = params.get(key)
            if value is not None:
                args.extend([flag, str(value)])
        return args
