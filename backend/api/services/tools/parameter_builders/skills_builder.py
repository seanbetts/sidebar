"""Parameter builders for skills tooling."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class SkillsParameterBuilder(BaseParameterBuilder):
    """Builders for skill tooling arguments."""

    @staticmethod
    def build_assistant_identity_get_args(params: dict) -> list:
        """Build CLI arguments for assistant identity read."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_assistant_identity_update_args(params: dict) -> list:
        """Build CLI arguments for assistant identity updates."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)

        for field_name in ("name", "tone", "values", "boundaries"):
            if field_name in params and params[field_name] is not None:
                args.extend([f"--{field_name}", params[field_name]])
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args

    @staticmethod
    def build_assistant_identity_reset_args(params: dict) -> list:
        """Build CLI arguments for assistant identity reset."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args

    @staticmethod
    def build_assistant_soul_get_args(params: dict) -> list:
        """Build CLI arguments for assistant soul read."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_assistant_soul_update_args(params: dict) -> list:
        """Build CLI arguments for assistant soul updates."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        for field_name in (
            "purpose",
            "operating_principles",
            "adaptation_policy",
            "success_signals",
        ):
            if field_name in params and params[field_name] is not None:
                # CLI uses kebab-case flags, while tool schema keys are snake_case.
                args.extend([f"--{field_name.replace('_', '-')}", params[field_name]])
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args

    @staticmethod
    def build_assistant_soul_reset_args(params: dict) -> list:
        """Build CLI arguments for assistant soul reset."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args
