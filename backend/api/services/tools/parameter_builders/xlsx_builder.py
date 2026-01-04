"""Parameter builders for xlsx tools."""
from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class XlsxParameterBuilder(BaseParameterBuilder):
    """Builders for xlsx tool arguments."""

    @staticmethod
    def build_recalc_args(params: dict) -> list:
        """Build CLI arguments for xlsx recalc."""
        args = [params["file_path"]]
        if params.get("timeout_seconds") is not None:
            args.append(str(params["timeout_seconds"]))
        return args
