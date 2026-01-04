"""Parameter builders for docx tools."""
from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class DocxParameterBuilder(BaseParameterBuilder):
    """Builders for docx tool arguments."""

    @staticmethod
    def build_unpack_args(params: dict) -> list:
        """Build CLI arguments for docx unpack."""
        return [params["input_file"], params["output_dir"]]

    @staticmethod
    def build_pack_args(params: dict) -> list:
        """Build CLI arguments for docx pack."""
        return [params["input_dir"], params["output_file"]]

    @staticmethod
    def build_validate_args(params: dict) -> list:
        """Build CLI arguments for docx validation."""
        args = [params["unpacked_dir"], "--original", params["original_file"]]
        if params.get("verbose"):
            args.append("--verbose")
        return args
