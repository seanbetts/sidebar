"""Tests for shared URL normalization service."""

import pytest

from api.services.url_normalization_service import (
    extract_youtube_video_id,
    is_youtube_host,
    normalize_website_url,
    normalize_youtube_url,
)


def test_is_youtube_host_strict_matching():
    assert is_youtube_host("youtube.com") is True
    assert is_youtube_host("www.youtube.com") is True
    assert is_youtube_host("m.youtube.com") is True
    assert is_youtube_host("youtu.be") is True
    assert is_youtube_host("www.youtu.be") is True
    assert is_youtube_host("notyoutube.com") is False
    assert is_youtube_host("example.com") is False


def test_extract_youtube_video_id_supported_variants():
    assert extract_youtube_video_id("https://youtu.be/abc123xyzAA") == "abc123xyzAA"
    assert (
        extract_youtube_video_id("https://www.youtube.com/watch?v=abc123xyzAA")
        == "abc123xyzAA"
    )
    assert (
        extract_youtube_video_id("https://www.youtube.com/shorts/abc123xyzAA")
        == "abc123xyzAA"
    )
    assert (
        extract_youtube_video_id("https://www.youtube.com/embed/abc123xyzAA")
        == "abc123xyzAA"
    )
    assert (
        extract_youtube_video_id("https://www.youtube.com/live/abc123xyzAA")
        == "abc123xyzAA"
    )


def test_extract_youtube_video_id_rejects_invalid():
    assert extract_youtube_video_id("https://example.com/watch?v=abc123xyzAA") is None
    assert extract_youtube_video_id("https://www.youtube.com/watch") is None
    assert extract_youtube_video_id("notaurl") is None


def test_normalize_youtube_url_to_canonical_watch_url():
    assert (
        normalize_youtube_url("youtu.be/abc123xyzAA?t=42")
        == "https://www.youtube.com/watch?v=abc123xyzAA"
    )
    assert (
        normalize_youtube_url("https://www.youtube.com/shorts/abc123xyzAA")
        == "https://www.youtube.com/watch?v=abc123xyzAA"
    )


def test_normalize_youtube_url_invalid():
    with pytest.raises(ValueError, match="Invalid YouTube URL"):
        normalize_youtube_url("https://example.com/watch?v=abc123xyzAA")


def test_normalize_website_url_youtube_uses_canonical_watch_url():
    assert (
        normalize_website_url("https://www.youtube.com/watch?v=abc123xyzAA&list=PL123")
        == "https://www.youtube.com/watch?v=abc123xyzAA"
    )
    assert (
        normalize_website_url("https://youtu.be/abc123xyzAA?t=10")
        == "https://www.youtube.com/watch?v=abc123xyzAA"
    )


def test_normalize_website_url_non_youtube_drops_query_and_fragment():
    assert (
        normalize_website_url("example.com/path?utm_source=test#section")
        == "https://example.com/path"
    )


def test_normalize_website_url_invalid():
    with pytest.raises(ValueError, match="Invalid URL"):
        normalize_website_url("https:///tmp/doc.txt")
