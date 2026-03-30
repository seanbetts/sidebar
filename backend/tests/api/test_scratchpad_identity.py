from api.services.scratchpad_identity import (
    LEGACY_SCRATCHPAD_TITLE,
    SCRATCHPAD_TITLE,
    is_scratchpad_title,
    scratchpad_document,
    strip_scratchpad_heading,
)


def test_is_scratchpad_title_matches_canonical_and_legacy_titles():
    assert is_scratchpad_title(SCRATCHPAD_TITLE) is True
    assert is_scratchpad_title(LEGACY_SCRATCHPAD_TITLE) is True
    assert is_scratchpad_title("Regular Note") is False


def test_strip_scratchpad_heading_removes_legacy_markdown_heading():
    content = f"{LEGACY_SCRATCHPAD_TITLE}\n\nBody line\nSecond line\n"

    assert strip_scratchpad_heading(content) == "Body line\nSecond line"


def test_scratchpad_document_builds_fixed_title_block_zero():
    document = scratchpad_document(f"{LEGACY_SCRATCHPAD_TITLE}\n\nBody line")

    assert document == {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": SCRATCHPAD_TITLE, "marks": []}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body line", "marks": []}],
            },
        ],
    }
