"""Parameter builders for skills tooling."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class SkillsParameterBuilder(BaseParameterBuilder):
    """Builders for skill tooling arguments."""

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
