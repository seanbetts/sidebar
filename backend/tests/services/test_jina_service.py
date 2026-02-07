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
