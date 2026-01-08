"""Tests for website transcript helpers."""

from api.services.website_transcript_service import (
    append_transcript_to_markdown,
    extract_youtube_id,
    normalize_youtube_url,
)


def test_extract_youtube_id_handles_watch_url():
    video_id = extract_youtube_id("https://www.youtube.com/watch?v=FUq9qRwrDrI")
    assert video_id == "FUq9qRwrDrI"


def test_normalize_youtube_url_handles_short_links():
    url = normalize_youtube_url("https://youtu.be/FUq9qRwrDrI")
    assert url == "https://www.youtube.com/watch?v=FUq9qRwrDrI"


def test_normalize_youtube_url_rejects_invalid():
    try:
        normalize_youtube_url("https://example.com/watch?v=bad")
    except ValueError as exc:
        assert "Invalid YouTube URL" in str(exc)
    else:
        raise AssertionError("Expected ValueError for invalid YouTube URL")


def test_append_transcript_appends_block_to_end():
    markdown = "\n".join(
        [
            "---",
            "title: Example",
            "---",
            "",
            "[YouTube](https://www.youtube.com/watch?v=FUq9qRwrDrI)",
            "",
            "Body text",
        ]
    )
    result = append_transcript_to_markdown(
        markdown,
        youtube_url="https://www.youtube.com/watch?v=FUq9qRwrDrI",
        transcript_text="Hello transcript",
        video_title="Example Video",
    )
    assert result.changed is True
    assert "YOUTUBE_TRANSCRIPT:FUq9qRwrDrI" in result.content
    assert "Hello transcript" in result.content
    assert result.content.rstrip().endswith("Hello transcript")
    assert "___" in result.content
    assert "Transcript of Example Video video" in result.content


def test_append_transcript_strips_transcript_frontmatter():
    markdown = "[YouTube](https://www.youtube.com/watch?v=FUq9qRwrDrI)\n"
    transcript = "\n".join(
        [
            "---",
            "title: Example",
            "source: https://youtube.com/watch?v=FUq9qRwrDrI",
            "---",
            "",
            "Transcript body line one.",
        ]
    )
    result = append_transcript_to_markdown(
        markdown,
        youtube_url="https://www.youtube.com/watch?v=FUq9qRwrDrI",
        transcript_text=transcript,
        video_title="Sample",
    )
    assert result.changed is True
    assert "title: Example" not in result.content
    assert "Transcript body line one." in result.content
    assert "Transcript of Sample video" in result.content


def test_append_transcript_strips_hash_header_block():
    markdown = "[YouTube](https://www.youtube.com/watch?v=FUq9qRwrDrI)\n"
    transcript = "\n".join(
        [
            "# Transcript of Example.mp3",
            "# Generated: 2026-01-06 18:30:33",
            "# Model: gpt-4o-transcribe",
            "---",
            "",
            "Final transcript line.",
        ]
    )
    result = append_transcript_to_markdown(
        markdown,
        youtube_url="https://www.youtube.com/watch?v=FUq9qRwrDrI",
        transcript_text=transcript,
        video_title="Example",
    )
    assert result.changed is True
    assert "Transcript of Example.mp3" not in result.content
    assert "Final transcript line." in result.content
    assert "Transcript of Example video" in result.content
