"""Shared helpers for parameter builders."""
from __future__ import annotations


class BaseParameterBuilder:
    """Common parameter builder helpers."""

    @staticmethod
    def append_user_id(args: list, params: dict) -> list:
        """Append --user-id if present.

        Args:
            args: Existing args list.
            params: Tool params.

        Returns:
            Updated args list.
        """
        user_id = params.get("user_id")
        if user_id:
            args.extend(["--user-id", user_id])
        return args

    @staticmethod
    def append_json(args: list) -> list:
        """Append --json flag.

        Args:
            args: Existing args list.

        Returns:
            Updated args list.
        """
        args.append("--json")
        return args
