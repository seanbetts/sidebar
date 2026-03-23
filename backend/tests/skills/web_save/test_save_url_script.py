"""Tests for web-save save_url script behaviors."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace

from api.services.web_save_antibot import AntibotDetection
from api.services.web_save_parser import LocalParseFallbackError

import pytest


def _load_save_url_module():
    script_path = (
        Path(__file__).resolve().parents[3]
        / "skills"
        / "web-save"
        / "scripts"
        / "save_url.py"
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
    module.get_markdown_content = (
        lambda url, api_key: captured_fetch.setdefault("url", url) or "ignored"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "WSJ Story",
            "url_source": "https://www.wsj.com/tech/ai/story-id",
            "published_time": None,
        },
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

    with pytest.raises(module.WebSaveScriptError) as exc_info:
        module.save_url_database("https://www.satchelone.com/todos/upcoming", "user-1")

    err = exc_info.value
    assert err.error_type == "FetchError"
    assert err.payload["code"] == "WEB_SAVE_LOCAL_PARSE_AND_JINA_PAYMENT_REQUIRED"
    assert "local parser found no readable content" in err.payload["message"].lower()


def test_save_url_database_antibot_local_failure_calls_jina_once(monkeypatch):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)
    jina_calls: list[str] = []

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url

    detection = AntibotDetection("cloudflare", "Just a moment... challenge")

    def antibot_parse(_url):
        raise LocalParseFallbackError(
            fallback="jina",
            rule_id="antibot-fetch-challenge",
            antibot_detection=detection,
            stage="fetch",
        )

    module.parse_url_local = antibot_parse
    module.get_markdown_content = lambda url, _key: jina_calls.append(url) or (
        "Title: Story\n"
        "URL Source: https://example.com/story\n"
        "Markdown Content:\n"
        "Body paragraph.\n"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Story",
            "url_source": "https://example.com/story",
            "published_time": None,
        },
        "Body paragraph.\n",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    module.save_url_database("https://example.com/story", "user-1")

    assert jina_calls == ["https://example.com/story"]
    assert captured["upsert_kwargs"]["title"] == "Story"


def test_save_url_database_antibot_fallback_not_reported_to_sentry(monkeypatch):
    module = _load_save_url_module()
    _stub_db_dependencies(module)
    capture_calls: list[str] = []
    exception_logs: list[str] = []

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")

    module.capture_script_exception = lambda exc, **kwargs: capture_calls.append(
        f"{type(exc).__name__}:{kwargs.get('extras')}"
    )
    module.logger.exception = lambda *args, **_kwargs: exception_logs.append(args[0])
    module.resolve_apple_news_source_url = lambda url: url

    detection = AntibotDetection("cloudflare", "Just a moment... challenge")

    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        LocalParseFallbackError(
            fallback="jina",
            rule_id="antibot-fetch-challenge",
            antibot_detection=detection,
            stage="fetch",
        )
    )
    module.get_markdown_content = lambda _url, _key: (
        "Title: Story\n"
        "URL Source: https://example.com/story\n"
        "Markdown Content:\n"
        "Body paragraph.\n"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Story",
            "url_source": "https://example.com/story",
            "published_time": None,
        },
        "Body paragraph.\n",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    module.save_url_database("https://example.com/story", "user-1")

    assert capture_calls == []
    assert exception_logs == []


def test_save_url_database_antibot_jina_blocked_content(monkeypatch):
    module = _load_save_url_module()
    _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url

    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        LocalParseFallbackError(
            fallback="jina",
            rule_id="antibot-fetch-challenge",
            antibot_detection=AntibotDetection(
                "generic", "challenge-form detected"
            ),
            stage="fetch",
        )
    )
    module.get_markdown_content = lambda _url, _key: (
        "<html>"
        "<head><title>Just a moment...</title></head>"
        "<body>"
        "<div class=\"cf-browser-verification\">Checking your browser before accessing</div>"
        "</body></html>"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Blocked Story",
            "url_source": "https://example.com/story",
            "published_time": None,
        },
        "Body",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    with pytest.raises(module.WebSaveScriptError) as exc_info:
        module.save_url_database("https://example.com/story", "user-1")

    err = exc_info.value
    assert err.payload["code"] == "WEB_SAVE_BLOCKED_SITE"


def test_save_url_database_antibot_jina_reuters_shell_content_is_rejected(
    monkeypatch,
):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url

    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        LocalParseFallbackError(
            fallback="jina",
            rule_id="antibot-fetch-challenge",
            antibot_detection=AntibotDetection(
                "generic", "captcha-delivery.com challenge"
            ),
            stage="fetch",
        )
    )
    module.get_markdown_content = lambda _url, _key: (
        "Title: Exclusive: OpenAI courts private equity to join enterprise AI venture, sources say | Reuters\n"
        "URL Source: https://www.reuters.com/business/openai-courts-private-equity-join-enterprise-ai-venture-sources-say-2026-03-16/\n"
        "Markdown Content:\n"
        "[Purchase Licensing Rights](https://www.reutersagency.com/en/licensereuterscontent/)\n\n"
        "[Milana Vinn](https://www.reuters.com/authors/milana-vinn/)\n"
        "Thomson Reuters\n\n"
        "Milana Vinn reports on technology, media, and telecom (TMT) mergers and acquisitions.\n\n"
        "## Read Next\n\n"
        "* [Another story](https://www.reuters.com/technology/example)\n\n"
        "## [Business](https://www.reuters.com/business/)\n\n"
        "* [Rail story](https://www.reuters.com/business/finance/example)\n\n"
        "### About Reuters\n\n"
        "Reuters, the news and media division of Thomson Reuters, is the world's largest multimedia news provider.\n\n"
        "### LSEG Products\n\n"
        "* [Workspace](https://www.lseg.com/en/data-analytics/products/workspace)\n"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": (
                "Exclusive: OpenAI courts private equity to join enterprise AI venture, "
                "sources say | Reuters"
            ),
            "url_source": (
                "https://www.reuters.com/business/"
                "openai-courts-private-equity-join-enterprise-ai-venture-sources-say-2026-03-16/"
            ),
            "published_time": None,
        },
        (
            "[Purchase Licensing Rights](https://www.reutersagency.com/en/licensereuterscontent/)\n\n"
            "[Milana Vinn](https://www.reuters.com/authors/milana-vinn/)\n"
            "Thomson Reuters\n\n"
            "Milana Vinn reports on technology, media, and telecom (TMT) mergers and acquisitions.\n\n"
            "## Read Next\n\n"
            "* [Another story](https://www.reuters.com/technology/example)\n\n"
            "## [Business](https://www.reuters.com/business/)\n\n"
            "* [Rail story](https://www.reuters.com/business/finance/example)\n\n"
            "### About Reuters\n\n"
            "Reuters, the news and media division of Thomson Reuters, is the world's largest multimedia news provider.\n\n"
            "### LSEG Products\n\n"
            "* [Workspace](https://www.lseg.com/en/data-analytics/products/workspace)\n"
        ),
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    with pytest.raises(module.WebSaveScriptError) as exc_info:
        module.save_url_database(
            "https://www.reuters.com/business/openai-courts-private-equity-join-enterprise-ai-venture-sources-say-2026-03-16/",
            "user-1",
        )

    err = exc_info.value
    assert err.payload["code"] == "WEB_SAVE_BLOCKED_SITE"
    assert "upsert_kwargs" not in captured


def test_save_url_database_jina_fastcompany_preview_is_cleaned(monkeypatch):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url

    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        LocalParseFallbackError(
            fallback="jina",
            rule_id="antibot-fetch-challenge",
            antibot_detection=AntibotDetection(
                "generic", "captcha-delivery.com challenge"
            ),
            stage="fetch",
        )
    )
    preview_content = (
        "03-23-2026[MOST INNOVATIVE COMPANIES](https://www.fastcompany.com/section/most-innovative-companies)\n\n"
        "[# Google CEO Sundar Pichai’s plan to make Gemini the only AI that matters]"
        "(https://www.fastcompany.com/91502632/google-most-innovative-companies-2026)\n\n"
        "Under Pichai, the company that invented modern AI is finally winning the race to deploy it.\n\n"
        "SHARE\n\n"
        "Facebook LinkedIn Bluesky X Link\n\n"
        "ADD ON GOOGLE\n\n"
        "![Image 4: Google CEO Sundar Pichai’s plan to make Gemini the only AI that matters]"
        "(https://images.fastcompany.com/hero.jpg)\n\n"
        "**Sundar Pichai**, CEO Of Google And Parent Company Alphabet\n\n"
        "![Image 5: Author's image](https://images.fastcompany.com/author.jpg)\n"
        "BY[Harry McCracken](https://www.fastcompany.com/user/harry-mccracken)\n\n"
        "Listen to this Article[More info](https://www.fastcompany.com/about-us#voice)\n\n"
        "0:00 / 0:00\n\n"
        "Sundar Pichai was blindsided by ChatGPT. Soon after being named Google CEO in 2015, he’d declared that the world was entering an AI-first era.\n\n"
        "Pichai remembers his instinctive response to ChatGPT: “Wow, this technology is going to diffuse earlier and faster than we were expecting.”\n\n"
        "Expand to continue reading ↓\n\n"
        "#### Explore Topics\n\n"
        "* [google](https://www.fastcompany.com/section/google)\n\n"
        "Featured Video\n\n"
        "Fast Company & Inc © 2026 Mansueto Ventures, LLC\n"
    )
    module.get_markdown_content = lambda _url, _key: (
        "Title: Sundar Pichai’s plan to make Google Gemini the only AI that matters - Fast Company\n"
        "URL Source: https://www.fastcompany.com/91502632/google-most-innovative-companies-2026\n"
        "Markdown Content:\n"
        f"{preview_content}"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Sundar Pichai’s plan to make Google Gemini the only AI that matters - Fast Company",
            "url_source": "https://www.fastcompany.com/91502632/google-most-innovative-companies-2026",
            "published_time": None,
        },
        preview_content,
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    module.save_url_database(
        "https://www.fastcompany.com/91502632/google-most-innovative-companies-2026",
        "user-1",
    )

    saved_content = captured["upsert_kwargs"]["content"]
    assert "SHARE" not in saved_content
    assert "Explore Topics" not in saved_content
    assert "Featured Video" not in saved_content
    assert "Fast Company & Inc" not in saved_content
    assert "By [Harry McCracken]" in saved_content
    assert "Sundar Pichai was blindsided by ChatGPT." in saved_content
    assert "Warning: This article appears truncated." in saved_content


def test_save_url_database_antibot_jina_fastcompany_shell_content_is_rejected(
    monkeypatch,
):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url

    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        LocalParseFallbackError(
            fallback="jina",
            rule_id="antibot-fetch-challenge",
            antibot_detection=AntibotDetection(
                "generic", "captcha-delivery.com challenge"
            ),
            stage="fetch",
        )
    )
    shell_content = (
        "LOGIN\n\n"
        "[SUBSCRIBE](https://www.fastcompany.com/subscribe)\n\n"
        "#### Explore Topics\n\n"
        "* [google](https://www.fastcompany.com/section/google)\n\n"
        "Featured Video\n\n"
        "More Videos\n\n"
        "#### Modern CEO\n\n"
        "Fast Company & Inc © 2026 Mansueto Ventures, LLC\n\n"
        "[search by queryly](https://www.queryly.com/)\n"
    )
    module.get_markdown_content = lambda _url, _key: (
        "Title: Fast Company shell\n"
        "URL Source: https://www.fastcompany.com/91502632/google-most-innovative-companies-2026\n"
        "Markdown Content:\n"
        f"{shell_content}"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Fast Company shell",
            "url_source": "https://www.fastcompany.com/91502632/google-most-innovative-companies-2026",
            "published_time": None,
        },
        shell_content,
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    with pytest.raises(module.WebSaveScriptError) as exc_info:
        module.save_url_database(
            "https://www.fastcompany.com/91502632/google-most-innovative-companies-2026",
            "user-1",
        )

    err = exc_info.value
    assert err.payload["code"] == "WEB_SAVE_BLOCKED_SITE"
    assert "upsert_kwargs" not in captured


def test_save_url_database_antibot_jina_timeout(monkeypatch):
    module = _load_save_url_module()
    _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url

    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        LocalParseFallbackError(
            fallback="jina",
            rule_id="antibot-fetch-challenge",
            antibot_detection=AntibotDetection(
                "generic", "challenge-form detected"
            ),
            stage="fetch",
        )
    )
    module.get_markdown_content = lambda _url, _key: (_ for _ in ()).throw(
        module.requests.exceptions.Timeout("request timed out")
    )
    module.logger.exception = lambda *_args, **_kwargs: None
    module.resolve_website_title = lambda title, url: title
    module.parse_jina_metadata = lambda _content: ({}, "")
    module.compute_word_count = lambda _content: 0
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    with pytest.raises(module.WebSaveScriptError) as exc_info:
        module.save_url_database("https://example.com/story", "user-1")

    err = exc_info.value
    assert err.payload["code"] == "WEB_SAVE_BLOCKED_SITE"


def test_save_url_database_local_parse_failure_with_jina_timeout_stays_generic(
    monkeypatch,
):
    module = _load_save_url_module()
    _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url

    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        ValueError("No readable content extracted")
    )
    module.get_markdown_content = lambda _url, _key: (_ for _ in ()).throw(
        module.requests.exceptions.Timeout(
            "Failed to fetch content from Jina.ai: request timed out"
        )
    )
    module.logger.exception = lambda *_args, **_kwargs: None
    module.resolve_website_title = lambda title, url: title
    module.parse_jina_metadata = lambda _content: ({}, "")
    module.compute_word_count = lambda _content: 0
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    with pytest.raises(module.WebSaveScriptError) as exc_info:
        module.save_url_database("https://example.com/story", "user-1")

    err = exc_info.value
    assert err.payload["code"] == "WEB_SAVE_LOCAL_PARSE_AND_JINA_FETCH_FAILED"


def test_save_url_database_jina_wsj_preview_adds_truncation_warning(monkeypatch):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "jina")
    module.resolve_apple_news_source_url = lambda url: url
    module.get_markdown_content = lambda _url, _api_key: (
        "Title: WSJ Story\n"
        "URL Source: https://www.wsj.com/tech/ai/story-id\n"
        "Markdown Content:\n"
        "Continue reading your article with\n"
        "a WSJ subscription\n"
        "Copyright ©2026 Dow Jones & Company, Inc. All Rights Reserved. "
        "87990cbe856818d5eddac44c7b1cdeb8\n"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "WSJ Story",
            "url_source": "https://www.wsj.com/tech/ai/story-id",
            "published_time": None,
        },
        "Amanda Askell knew from the age of 14 that she wanted to teach philosophy.",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    module.save_url_database("https://www.wsj.com/tech/ai/story-id", "user-1")

    saved_content = captured["upsert_kwargs"]["content"]
    assert "Warning: This article appears truncated." in saved_content


def test_save_url_database_logs_jina_fallback_events(monkeypatch):
    module = _load_save_url_module()
    _stub_db_dependencies(module)
    logged: list[tuple[str, tuple]] = []

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.resolve_apple_news_source_url = lambda url: url
    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        RuntimeError("Browser executable missing")
    )
    module.get_markdown_content = lambda _url, _api_key: (
        "Title: Story\n"
        "URL Source: https://www.theverge.com/ai/story-id\n"
        "Markdown Content:\n"
        "Subscribe now\n"
        "[Link](https://example.com)\n"
        "Body paragraph.\n"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Story",
            "url_source": "https://www.theverge.com/ai/story-id",
            "published_time": None,
        },
        "Body paragraph.\n[Link](https://example.com)\n",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []
    module.logger.info = lambda message, *args: logged.append((message, args))
    module.logger.exception = lambda *_args, **_kwargs: None

    module.save_url_database("https://www.theverge.com/ai/story-id", "user-1")

    assert any("web-save fallback start" in message for message, _ in logged)
    result_messages = [
        message for message, _ in logged if "web-save fallback result" in message
    ]
    assert result_messages
    assert any("raw_link_density_pct" in message for message in result_messages)
    assert any("clean_link_density_pct" in message for message in result_messages)
    assert any("raw_trunc_markers" in message for message in result_messages)
    assert any("clean_trunc_markers" in message for message in result_messages)


def test_save_url_database_initializes_script_sentry(monkeypatch):
    module = _load_save_url_module()
    _stub_db_dependencies(module)
    initialized: list[str] = []

    monkeypatch.setenv("WEB_SAVE_MODE", "jina")
    module.initialize_script_sentry = lambda script_name: initialized.append(script_name)
    module.resolve_apple_news_source_url = lambda url: url
    module.get_markdown_content = lambda _url, _api_key: (
        "Title: Story\n"
        "URL Source: https://example.com/story\n"
        "Markdown Content:\n"
        "Body paragraph.\n"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Story",
            "url_source": "https://example.com/story",
            "published_time": None,
        },
        "Body paragraph.\n",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []

    module.save_url_database("https://example.com/story", "user-1")

    assert initialized == ["web-save.save_url"]


def test_save_url_database_reports_local_parse_failure_to_sentry(monkeypatch):
    module = _load_save_url_module()
    _stub_db_dependencies(module)
    captured: list[tuple[BaseException, dict | None]] = []

    monkeypatch.setenv("WEB_SAVE_MODE", "local")
    monkeypatch.setenv("JINA_API_KEY", "test-key")
    module.initialize_script_sentry = lambda _script_name: None
    module.capture_script_exception = (
        lambda exc, *, extras=None: captured.append((exc, extras))
    )
    module.resolve_apple_news_source_url = lambda url: url
    module.parse_url_local = lambda _url: (_ for _ in ()).throw(
        RuntimeError("Browser executable missing")
    )
    module.get_markdown_content = lambda _url, _api_key: (
        "Title: Story\n"
        "URL Source: https://www.theverge.com/ai/story-id\n"
        "Markdown Content:\n"
        "Body paragraph.\n"
    )
    module.parse_jina_metadata = lambda _content: (
        {
            "title": "Story",
            "url_source": "https://www.theverge.com/ai/story-id",
            "published_time": None,
        },
        "Body paragraph.\n",
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda content: len(content.split())
    module.calculate_reading_time = lambda _count: "1 min"
    module.extract_tags = lambda *_args, **_kwargs: []
    module.logger.exception = lambda *_args, **_kwargs: None

    module.save_url_database("https://www.theverge.com/ai/story-id", "user-1")

    assert len(captured) == 1
    assert str(captured[0][0]) == "Browser executable missing"
    assert captured[0][1] == {
        "target_url": "https://www.theverge.com/ai/story-id",
        "mode": "local",
    }


def test_save_url_database_jina_uses_youtube_duration_for_reading_time(monkeypatch):
    module = _load_save_url_module()
    captured = _stub_db_dependencies(module)

    monkeypatch.setenv("WEB_SAVE_MODE", "jina")
    module.resolve_apple_news_source_url = lambda url: url
    module.get_markdown_content = lambda _url, _api_key: (
        "Title: Video Story\n"
        "URL Source: https://www.youtube.com/watch?v=abc123xyzAA\n"
        "Markdown Content:\n"
        "[YouTube](https://www.youtube.com/watch?v=abc123xyzAA)\n"
    )
    module.resolve_website_title = lambda title, url: title
    module.compute_word_count = lambda _content: 1
    module.calculate_reading_time = lambda _count: (_ for _ in ()).throw(
        AssertionError("text-based reading time should not be used for YouTube")
    )
    module.fetch_youtube_duration_seconds = lambda _url: 214
    module.reading_time_from_duration_seconds = (
        lambda seconds: "4 mins" if seconds == 214 else None
    )
    module.extract_tags = lambda *_args, **_kwargs: []

    module.save_url_database("https://www.youtube.com/watch?v=abc123xyzAA", "user-1")

    saved_content = captured["upsert_kwargs"]["content"]
    assert "reading_time: 4 mins" in saved_content
