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
        "Reviews and recommendations, independent of The Wall Street Journal newsroom."
        not in cleaned
    )
    assert (
        "Real article continuation paragraph that should remain in output." in cleaned
    )


def test_clean_markdown_for_source_passthrough_non_wsj():
    markdown = "# Example\n\nBody"
    cleaned = JinaService.clean_markdown_for_source(markdown, "https://example.com/a")
    assert cleaned == "# Example\n\nBody"


def test_clean_markdown_for_source_universal_removes_noise_and_nav_blocks():
    markdown = """
Anthropic gives its retired Claude AI a Substack
===============================================

In January, Anthropic retired Claude 3 Opus and later brought it back as a blog writer.

Sign up for Verge Daily so you never miss out on the tech news that matters most.
close email sign up banner

*   [Tech](https://www.theverge.com/tech)
*   [Reviews](https://www.theverge.com/reviews)
*   [Science](https://www.theverge.com/science)
*   [Entertainment](https://www.theverge.com/entertainment)
*   [AI](https://www.theverge.com/ai-artificial-intelligence)
*   [Policy](https://www.theverge.com/policy)

The newsletter, called Claude's Corner, gives Opus 3 space to publish musings and creative work.

Privacy Center
--------------

![tracker](https://analytics.twitter.com/1/i/adsct?event=foo)
"""

    cleaned = JinaService.clean_markdown_for_source(
        markdown,
        "https://example.com/article",
    )

    assert "Sign up for Verge Daily" not in cleaned
    assert "close email sign up banner" not in cleaned
    assert "[Tech](https://www.theverge.com/tech)" not in cleaned
    assert "Privacy Center" not in cleaned
    assert "analytics.twitter.com/1/i/adsct" not in cleaned
    assert "Anthropic retired Claude 3 Opus" in cleaned
    assert "Claude's Corner" in cleaned


def test_clean_markdown_for_source_verge_trims_footer_and_privacy_sections():
    markdown = """
Anthropic gives its retired Claude AI a Substack
===============================================

After retiring Opus 3, Anthropic asked it what it wanted. The AI requested a blog.

In January, Anthropic “retired” Claude 3 Opus, which at one time was the company’s most powerful AI model.

Most Popular
------------

1. [Story A](https://www.theverge.com/a)
2. [Story B](https://www.theverge.com/b)

Privacy Center
--------------

Powered by Onetrust
"""

    cleaned = JinaService.clean_markdown_for_source(
        markdown,
        "https://www.theverge.com/ai-artificial-intelligence/885200/example",
    )

    assert "Most Popular" not in cleaned
    assert "Privacy Center" not in cleaned
    assert "Powered by Onetrust" not in cleaned
    assert "After retiring Opus 3" in cleaned
    assert "most powerful AI model" in cleaned


def test_clean_markdown_for_source_wsj_removes_footer_legal_and_trackers():
    markdown = """
Meet the One Woman Anthropic Trusts to Teach AI Morals
======================================================

The tech company has tasked Amanda Askell with giving its chatbot, Claude, a sense of right and wrong.
------------------------------------------------------------------------------------------------------

Amanda Askell knew from the age of 14 that she wanted to teach philosophy.

As the resident philosopher of the tech company Anthropic, Askell spends her days learning Claude's reasoning patterns.

*   [The Wall Street Journal](https://www.wsj.com/)
*   English Edition  Edition Use Alt + Down Arrow to expand.
*   Back to Top «

*   [Subscription Options](https://subscribe.wsj.com/membership)
*   [Corporate Subscriptions](https://corporate.wsj.com/?mod=djm_wsjfooter_44670)
*   [Jobs at WSJ](https://wsj.jobs/)
*   [Content Partnerships](https://wsj.com/partner)
*   [Dow Jones Smart Money](https://www.dowjones.com/smartmoney)

*   [Privacy Notice](https://www.dowjones.com/privacy-notice/?mod=WSJ)
*   [Legal Policies](https://www.wsj.com/policy/legal-policies)
*   [Terms of Use](https://www.dowjones.com/terms-of-use/)

[Sign In](https://www.wsj.com/client/login?target=https%3A%2F%2Fwww.wsj.com%2Ftech%2Fai%2Fanthropic-amanda-askell-philosopher-ai-3c031883)

Copyright ©2026 Dow Jones & Company, Inc. All Rights Reserved

This copy is for your personal, non-commercial use only. Distribution and use of this material are governed by our Subscriber Agreement.

![Image 12](https://analytics.twitter.com/1/i/adsct?event=foo)![Image 13](https://t.co/1/i/adsct?event=bar)
"""

    cleaned = JinaService.clean_markdown_for_source(
        markdown,
        "https://www.wsj.com/tech/ai/anthropic-amanda-askell-philosopher-ai-3c031883",
    )

    assert "Amanda Askell knew from the age of 14" in cleaned
    assert "As the resident philosopher of the tech company Anthropic" in cleaned
    assert "Subscription Options" not in cleaned
    assert "Privacy Notice" not in cleaned
    assert "Content Partnerships" not in cleaned
    assert "Dow Jones Smart Money" not in cleaned
    assert "Sign In](https://www.wsj.com/client/login?target=" not in cleaned
    assert "This copy is for your personal, non-commercial use only." not in cleaned
    assert "analytics.twitter.com/1/i/adsct" not in cleaned
    assert "t.co/1/i/adsct" not in cleaned


def test_clean_markdown_for_source_wsj_dedupes_repeated_long_paragraphs():
    repeated = (
        "As the resident philosopher of the tech company Anthropic, Askell spends "
        "her days learning Claude's reasoning patterns and talking to the AI model."
    )
    markdown = f"""
Meet the One Woman Anthropic Trusts to Teach AI Morals
======================================================

{repeated}

{repeated}
"""

    cleaned = JinaService.clean_markdown_for_source(
        markdown,
        "https://www.wsj.com/tech/ai/anthropic-amanda-askell-philosopher-ai-3c031883",
    )

    assert cleaned.count(repeated) == 1


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
