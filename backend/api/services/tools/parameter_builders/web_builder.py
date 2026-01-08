"""Parameter builders for web tools."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class WebParameterBuilder(BaseParameterBuilder):
    """Builders for web tool arguments."""

    @staticmethod
    def build_subdomain_discover_args(params: dict) -> list:
        """Build CLI arguments for subdomain discovery."""
        args = [params["domain"], "--json"]
        if params.get("wordlist"):
            args.extend(["--wordlist", params["wordlist"]])
        if params.get("timeout") is not None:
            args.extend(["--timeout", str(params["timeout"])])
        if params.get("dns_timeout") is not None:
            args.extend(["--dns-timeout", str(params["dns_timeout"])])
        if params.get("no_filter"):
            args.append("--no-filter")
        if params.get("verbose"):
            args.append("--verbose")
        return args

    @staticmethod
    def build_crawler_policy_args(params: dict) -> list:
        """Build CLI arguments for crawler policy analysis."""
        args = [params["domain"], "--json"]
        WebParameterBuilder.append_user_id(args, params)
        if params.get("no_discover"):
            args.append("--no-discover")
        if params.get("wordlist"):
            args.extend(["--wordlist", params["wordlist"]])
        if params.get("timeout") is not None:
            args.extend(["--timeout", str(params["timeout"])])
        if params.get("dns_timeout") is not None:
            args.extend(["--dns-timeout", str(params["dns_timeout"])])
        if params.get("no_llms"):
            args.append("--no-llms")
        return args
