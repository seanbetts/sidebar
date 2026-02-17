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
                args.extend([f"--{field_name}", params[field_name]])
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

    @staticmethod
    def build_skill_package_args(params: dict) -> list:
        """Build CLI arguments for skill packaging."""
        args = [params["skill_dir"]]
        if params.get("output_dir"):
            args.append(params["output_dir"])
        return args

    @staticmethod
    def build_mcp_evaluation_args(params: dict) -> list:
        """Build CLI arguments for MCP evaluation runs."""
        args = [params["eval_file"]]
        if params.get("transport"):
            args.extend(["--transport", params["transport"]])
        if params.get("model"):
            args.extend(["--model", params["model"]])
        if params.get("command"):
            args.extend(["--command", params["command"]])
        if params.get("args"):
            args.extend(["--args", *params["args"]])
        if params.get("env"):
            args.extend(["--env", *params["env"]])
        if params.get("url"):
            args.extend(["--url", params["url"]])
        if params.get("headers"):
            args.extend(["--header", *params["headers"]])
        if params.get("output"):
            args.extend(["--output", params["output"]])
        return args
