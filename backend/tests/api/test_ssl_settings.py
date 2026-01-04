import ssl
from pathlib import Path

import pytest

from api.config import Settings
from api.services.claude_client import ClaudeClient


def _build_http_client(settings: Settings):
    client = ClaudeClient.__new__(ClaudeClient)
    return client._create_http_client(settings)


def test_ssl_disabled_in_production_raises_error() -> None:
    with pytest.raises(ValueError):
        Settings(app_env="production", disable_ssl_verify=True, anthropic_api_key="test-key")


def test_ssl_can_be_disabled_in_development() -> None:
    settings = Settings(app_env="development", disable_ssl_verify=True, anthropic_api_key="test-key")
    http_client = _build_http_client(settings)
    ssl_context = http_client._transport._ssl_context
    assert ssl_context is not None
    assert ssl_context.verify_mode == ssl.CERT_NONE


def test_custom_ca_bundle_is_loaded(tmp_path: Path) -> None:
    ca_bundle = tmp_path / "ca.pem"
    ca_bundle.write_text("", encoding="utf-8")
    settings = Settings(app_env="production", custom_ca_bundle=str(ca_bundle), anthropic_api_key="test-key")
    http_client = _build_http_client(settings)
    ssl_context = http_client._transport._ssl_context
    assert ssl_context is not None
