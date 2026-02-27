"""Tests for JinaService metadata parsing safeguards."""

import httpx
import pytest

from api.services import jina_service
from api.services.jina_service import JinaFetchError, JinaService


def test_parse_metadata_cleans_undefined_url_source():
    markdown = (
        "Title: Example\n"
        "URL Source: undefined\n"
        "Published Time: 2026-02-07T00:00:00Z\n"
        "Markdown Content:\n"
        "# Body\n"
    )

    metadata, cleaned = JinaService.parse_metadata(markdown)

    assert metadata["title"] == "Example"
    assert metadata["url_source"] is None
    assert metadata["published_time"] == "2026-02-07T00:00:00Z"
    assert cleaned.startswith("# Body")


def test_parse_metadata_cleans_null_like_values():
    markdown = (
        "Title: null\nURL Source: N/A\nPublished Time: none\nMarkdown Content:\nHello\n"
    )

    metadata, _cleaned = JinaService.parse_metadata(markdown)

    assert metadata["title"] is None
    assert metadata["url_source"] is None
    assert metadata["published_time"] is None


def test_extract_title_strips_youtube_suffix():
    markdown = (
        "# OpenAI Super Bowl 2026 | Codex | You Can Just Build Things - YouTube\n\nBody"
    )

    title = JinaService.extract_title(
        markdown,
        "https://www.youtube.com/watch?v=aCN9iCXNJqQ",
    )

    assert title == "OpenAI Super Bowl 2026 | Codex | You Can Just Build Things"


def test_parse_metadata_extracts_reading_time():
    markdown = (
        "Title: Example Video\n"
        "URL Source: https://www.youtube.com/watch?v=abc123xyzAA\n"
        "Reading Time: 11 min\n"
        "Markdown Content:\n"
        "[YouTube](https://www.youtube.com/watch?v=abc123xyzAA)\n"
    )

    metadata, cleaned = JinaService.parse_metadata(markdown)

    assert metadata["reading_time"] == "11 min"
    assert "Reading Time:" not in cleaned


def test_clean_markdown_for_source_wsj_trims_navigation_and_paywall():
    markdown = """
Anthropic’s Philosopher Amanda Askell Is Teaching Claude AI to Have Morals - WSJ
===============

Skip to Main Content

Meet the One Woman Anthropic Trusts to Teach AI Morals
======================================================

The tech company has tasked Amanda Askell with giving its chatbot, Claude, a sense of right and wrong.
------------------------------------------------------------------------------------------------------

By

[Berber Jin](https://www.wsj.com/news/author/berber-jin)

Feb. 9, 2026 7:00 am ET

Amanda Askell knew from the age of 14 that she wanted to teach philosophy.

Continue reading your article with

a WSJ subscription

Later paragraph that should remain in output.

Copyright ©2026 Dow Jones & Company, Inc. All Rights Reserved. 87990cbe856818d5eddac44c7b1cdeb8

![Image 4: The Wall Street Journal](https://sts3.wsj.net/iweb/images/wsj-logo-big-black.svg)

[235](https://www.wsj.com/tech/ai/anthropic-amanda-askell-philosopher-ai-3c031883#comments_sector)

[WSJ | Buy Side](https://www.wsj.com/buyside/?mod=wsj_article_buy_widget)
Reviews and recommendations, independent of The Wall Street Journal newsroom.

Real article continuation paragraph that should remain in output.

News
*   [Live Coverage](https://www.wsj.com/livecoverage?mod=wsjfooter)

Customer Service
*   [Customer Center](https://customercenter.wsj.com/home)
"""

    cleaned = JinaService.clean_markdown_for_source(
        markdown,
        "https://www.wsj.com/tech/ai/anthropic-amanda-askell-philosopher-ai-3c031883",
    )

    assert "Skip to Main Content" not in cleaned
    assert "Continue reading your article with" not in cleaned
    assert "Amanda Askell knew from the age of 14" in cleaned
    assert "Later paragraph that should remain in output." in cleaned
    assert "#comments_sector" not in cleaned
    assert "Dow Jones & Company, Inc. All Rights Reserved" not in cleaned
    assert (
        "The Wall Street Journal](https://sts3.wsj.net/iweb/images/wsj-logo-big-black.svg)"
        not in cleaned
    )
    assert "Buy Side" not in cleaned
    assert "mod=wsjfooter" not in cleaned
    assert (
        "Real article continuation paragraph that should remain in output." in cleaned
    )


def test_clean_markdown_for_source_passthrough_non_wsj():
    markdown = "# Example\n\nBody"
    cleaned = JinaService.clean_markdown_for_source(markdown, "https://example.com/a")
    assert cleaned == "# Example\n\nBody"


def _status_response(status_code: int, url: str, text: str = "") -> httpx.Response:
    request = httpx.Request("GET", url)
    return httpx.Response(status_code, request=request, text=text)


def test_fetch_markdown_retries_anonymous_after_auth_402(monkeypatch):
    calls: list[dict | None] = []

    class FakeClient:
        def __init__(self, timeout: float):
            assert timeout == 30.0

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            return None

        def get(self, url: str, headers: dict | None = None):
            calls.append(headers)
            if len(calls) == 1:
                return _status_response(
                    status_code=402, url=url, text="Payment Required"
                )
            return _status_response(status_code=200, url=url, text="# Full article")

    monkeypatch.setattr(jina_service.settings, "jina_api_key", "test-key")
    monkeypatch.setattr(jina_service.httpx, "Client", FakeClient)

    markdown = JinaService.fetch_markdown("https://example.com/story")

    assert markdown == "# Full article"
    assert calls[0] == {"Authorization": "Bearer test-key"}
    assert calls[1] is None


def test_fetch_markdown_raises_when_auth_and_anonymous_fail(monkeypatch):
    class FakeClient:
        def __init__(self, timeout: float):
            assert timeout == 30.0

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            return None

        def get(self, url: str, headers: dict | None = None):
            status_code = 402 if headers else 451
            return _status_response(status_code=status_code, url=url)

    monkeypatch.setattr(jina_service.settings, "jina_api_key", "test-key")
    monkeypatch.setattr(jina_service.httpx, "Client", FakeClient)

    with pytest.raises(JinaFetchError) as exc_info:
        JinaService.fetch_markdown("https://example.com/story")

    err = exc_info.value
    assert err.auth_status_code == 402
    assert err.anonymous_status_code == 451
    assert "authenticated request returned 402" in str(err)
