"""Tests for web-save save_url script behaviors."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest


def _load_save_url_module():
    script_path = (
        Path(__file__).resolve().parents[3] / "skills" / "web-save" / "scripts" / "save_url.py"
    )
    spec = importlib.util.spec_from_file_location("save_url_script", script_path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _stub_db_dependencies(module):
    captured: dict = {}

    class FakeSession:
        def close(self):
            return None

    class FakeWebsitesService:
        @staticmethod
        def upsert_website(db, user_id, **kwargs):
            captured["upsert_kwargs"] = kwargs
            return SimpleNamespace(
                id="website-id",
                title=kwargs["title"],
                url=kwargs["url"],
                domain="example.com",
            )

    module.SessionLocal = lambda: FakeSession()
    module.set_session_user_id = lambda db, user_id: None
    module.WebsitesService = FakeWebsitesService
    module.FaviconService = None
    module.extract_favicon_url = lambda _url: None
    return captured


def test_save_url_database_jina_resolves_apple_news_target(monkeypatch):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)
    captured_fetch: dict = {}

    monkeypatch.setenv("WEB_SAVE_MODE", "jina")
    module.resolve_apple_news_source_url = (
        lambda _url: "https://www.wsj.com/tech/ai/story-id"
    )
    module.get_markdown_content = lambda url, api_key: captured_fetch.setdefault(
        "url", url
    ) or "ignored"
    module.parse_jina_metadata = lambda _content: (
        {"title": "WSJ Story", "url_source": "https://www.wsj.com/tech/ai/story-id", "published_time": None},
        "Story body",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda _content: 2
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    module.save_url_database("https://apple.news/ASNJScnjXQj-AP4JENCN9NQ", "user-1")

    assert captured_fetch["url"] == "https://www.wsj.com/tech/ai/story-id"
    assert captured["upsert_kwargs"]["source"] == "https://www.wsj.com/tech/ai/story-id"


def test_save_url_database_local_uses_resolved_target(monkeypatch):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)
    captured_parse: dict = {}

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    module.resolve_apple_news_source_url = (
        lambda _url: "https://www.wsj.com/tech/ai/story-id"
    )

    def fake_parse(url):
        captured_parse["url"] = url
        return module.ParsedPage(
            title="Local Parsed",
            content="---\nsource: https://www.wsj.com/tech/ai/story-id\n---\n\nBody\n",
            source="https://www.wsj.com/tech/ai/story-id",
            published_at=None,
        )

    module.parse_url_local = fake_parse

    module.save_url_database("https://apple.news/ASNJScnjXQj-AP4JENCN9NQ", "user-1")

    assert captured_parse["url"] == "https://www.wsj.com/tech/ai/story-id"
    assert captured["upsert_kwargs"]["source"] == "https://www.wsj.com/tech/ai/story-id"


def test_save_url_database_reports_local_and_jina_failure(monkeypatch):
    module = _load_save_url_module()
    _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    module.resolve_apple_news_source_url = lambda url: url

    def fail_local(_url):
        raise ValueError("No readable content extracted")

    module.parse_url_local = fail_local
    module.get_markdown_content = lambda _url, _api_key: (_ for _ in ()).throw(
        module.requests.exceptions.RequestException(
            "Failed to fetch content from Jina.ai: 402 Client Error: Payment Required"
        )
    )
    monkeypatch.setenv("JINA_API_KEY", "test-key")

    with pytest.raises(module.requests.exceptions.RequestException) as exc_info:
        module.save_url_database("https://www.satchelone.com/todos/upcoming", "user-1")

    message = str(exc_info.value)
    assert "Local parse failed (No readable content extracted)" in message
    assert "Jina fallback failed" in message
