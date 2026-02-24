"""Tests for JinaService metadata parsing safeguards."""

from api.services.jina_service import JinaService


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
        "Title: null\n"
        "URL Source: N/A\n"
        "Published Time: none\n"
        "Markdown Content:\n"
        "Hello\n"
    )

    metadata, _cleaned = JinaService.parse_metadata(markdown)

    assert metadata["title"] is None
    assert metadata["url_source"] is None
    assert metadata["published_time"] is None


def test_extract_title_strips_youtube_suffix():
    markdown = "# OpenAI Super Bowl 2026 | Codex | You Can Just Build Things - YouTube\n\nBody"

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
"""

    cleaned = JinaService.clean_markdown_for_source(
        markdown,
        "https://www.wsj.com/tech/ai/anthropic-amanda-askell-philosopher-ai-3c031883",
    )

    assert "Skip to Main Content" not in cleaned
    assert "Continue reading your article with" not in cleaned
    assert "Amanda Askell knew from the age of 14" in cleaned


def test_clean_markdown_for_source_passthrough_non_wsj():
    markdown = "# Example\n\nBody"
    cleaned = JinaService.clean_markdown_for_source(markdown, "https://example.com/a")
    assert cleaned == "# Example\n\nBody"
