import ssl
import types

import pytest

import httpx
from api.config import Settings
from api.services.claude_client import ClaudeClient


def _build_http_client(settings: Settings):
    client = ClaudeClient.__new__(ClaudeClient)
    return client._create_http_client(settings)


class DummySSLContext:
    def __init__(self) -> None:
        self.check_hostname = True
        self.verify_mode = ssl.CERT_REQUIRED
        self.loaded_path: str | None = None

    def load_verify_locations(self, cafile: str) -> None:
        self.loaded_path = cafile


def test_ssl_disabled_in_production_raises_error() -> None:
    with pytest.raises(ValueError):
        Settings(app_env="production", disable_ssl_verify=True, anthropic_api_key="test-key")


def test_ssl_can_be_disabled_in_development(monkeypatch: pytest.MonkeyPatch) -> None:
    dummy_context = DummySSLContext()
    monkeypatch.setattr(ssl, "create_default_context", lambda: dummy_context)
    monkeypatch.setattr(
        httpx,
        "AsyncClient",
        lambda **kwargs: types.SimpleNamespace(verify=kwargs.get("verify")),
    )

    settings = Settings(app_env="development", disable_ssl_verify=True, anthropic_api_key="test-key")
    http_client = _build_http_client(settings)

    assert dummy_context.verify_mode == ssl.CERT_NONE
    assert dummy_context.check_hostname is False
    assert http_client.verify is dummy_context


def test_custom_ca_bundle_is_loaded(monkeypatch: pytest.MonkeyPatch) -> None:
    dummy_context = DummySSLContext()
    monkeypatch.setattr(ssl, "create_default_context", lambda: dummy_context)
    monkeypatch.setattr(
        httpx,
        "AsyncClient",
        lambda **kwargs: types.SimpleNamespace(verify=kwargs.get("verify")),
    )

    settings = Settings(app_env="production", custom_ca_bundle="/tmp/ca.pem", anthropic_api_key="test-key")
    http_client = _build_http_client(settings)

    assert dummy_context.loaded_path == "/tmp/ca.pem"
    assert http_client.verify is dummy_context
