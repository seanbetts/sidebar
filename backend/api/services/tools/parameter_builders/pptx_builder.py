"""Parameter builders for pptx tools."""
from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class PptxParameterBuilder(BaseParameterBuilder):
    """Builders for pptx tool arguments."""

    @staticmethod
    def build_inventory_args(params: dict) -> list:
        """Build CLI arguments for pptx inventory."""
        args = [params["input_pptx"], params["output_json"]]
        if params.get("issues_only"):
            args.append("--issues-only")
        return args

    @staticmethod
    def build_thumbnail_args(params: dict) -> list:
        """Build CLI arguments for pptx thumbnail generation."""
        args = [params["input_pptx"]]
        if params.get("output_prefix"):
            args.append(params["output_prefix"])
        if params.get("cols") is not None:
            args.extend(["--cols", str(params["cols"])])
        if params.get("outline_placeholders"):
            args.append("--outline-placeholders")
        return args
