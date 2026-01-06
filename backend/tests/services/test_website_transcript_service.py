"""Tests for website transcript helpers."""
from api.services.website_transcript_service import append_transcript_to_markdown, extract_youtube_id


def test_extract_youtube_id_handles_watch_url():
    video_id = extract_youtube_id("https://www.youtube.com/watch?v=FUq9qRwrDrI")
    assert video_id == "FUq9qRwrDrI"


def test_append_transcript_inserts_marker_after_embed():
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
    )
    assert result.changed is True
    assert "YOUTUBE_TRANSCRIPT:FUq9qRwrDrI" in result.content
    assert "Hello transcript" in result.content


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
    )
    assert result.changed is True
    assert "title: Example" not in result.content
    assert "Transcript body line one." in result.content


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
    )
    assert result.changed is True
    assert "Transcript of Example.mp3" not in result.content
    assert "Final transcript line." in result.content
