"""Parameter builders for conversation tools."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class ConversationsParameterBuilder(BaseParameterBuilder):
    """Builders for conversation tool arguments."""

    @staticmethod
    def build_search_args(params: dict) -> list:
        """Build CLI arguments for conversation search."""
        args = [params["query"]]
        ConversationsParameterBuilder.append_user_id(args, params)
        if params.get("limit") is not None:
            args.extend(["--limit", str(params["limit"])])
        return args

    @staticmethod
    def build_rename_args(params: dict) -> list:
        """Build CLI arguments for conversation rename."""
        args = [params["conversation_id"]]
        ConversationsParameterBuilder.append_user_id(args, params)
        args.extend(["--new-name", params["new_name"]])
        return args
