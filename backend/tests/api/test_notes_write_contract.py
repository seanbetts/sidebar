import pytest
from api.exceptions import BadRequestError
from api.services.notes_document_types import note_document_from_plain_text
from api.services.notes_write_contract import (
    build_canonical_note_write,
    parse_note_write_payload,
)


def test_parse_note_write_payload_requires_document():
    with pytest.raises(BadRequestError, match="document required"):
        parse_note_write_payload({})


def test_parse_note_write_payload_rejects_explicit_title():
    with pytest.raises(BadRequestError, match="Note titles are derived from note content"):
        parse_note_write_payload(
            {
                "document": note_document_from_plain_text("# Title\n\nBody"),
                "title": "Manual Title",
            }
        )


def test_parse_note_write_payload_rejects_legacy_content_field():
    with pytest.raises(BadRequestError, match="Legacy note content payloads are unsupported"):
        parse_note_write_payload(
            {
                "document": note_document_from_plain_text("Semantic Title\nBody"),
                "content": "# Legacy markdown body",
            }
        )


def test_build_canonical_note_write_accepts_canonical_payload():
    document = {
        "version": 1,
        "blocks": [
            {"type": "title", "content": [{"text": "Strict title", "marks": []}]},
            {"type": "paragraph", "content": [{"text": "Body", "marks": []}]},
        ],
    }

    result = build_canonical_note_write(document)

    assert result.document == document
    assert result.document_version == 1
    assert result.plain_text == "Strict title\nBody"
    assert result.title == "Strict title"


def test_build_canonical_note_write_uses_title_block_zero_for_derived_title():
    document = {
        "version": 1,
        "blocks": [
            {"type": "title", "content": [{"text": "   ", "marks": []}]},
            {"type": "heading", "content": [{"text": "Heading text", "marks": []}]},
        ],
    }

    result = build_canonical_note_write(document)

    assert result.plain_text == "   \nHeading text"
    assert result.title == "New Note"


def test_build_canonical_note_write_promotes_legacy_paragraph_block_zero_to_title():
    document = {
        "version": 1,
        "blocks": [
            {"type": "paragraph", "content": [{"text": "Legacy title", "marks": []}]},
            {"type": "paragraph", "content": [{"text": "Body", "marks": []}]},
        ],
    }

    result = build_canonical_note_write(document)

    assert result.document["blocks"][0]["type"] == "title"
    assert result.plain_text == "Legacy title\nBody"
    assert result.title == "Legacy title"


def test_build_canonical_note_write_projects_link_labels_and_url_fallback():
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [
                    {
                        "text": "Sidebar Docs",
                        "marks": [],
                        "link": {"url": "https://example.com/docs"},
                    }
                ],
            },
            {
                "type": "paragraph",
                "content": [
                    {
                        "text": "",
                        "marks": [],
                        "link": {"url": "https://example.com/reference"},
                    }
                ],
            },
        ],
    }

    result = build_canonical_note_write(document)

    assert result.document == document
    assert result.plain_text == "Sidebar Docs\nhttps://example.com/reference"
    assert result.title == "Sidebar Docs"


def test_build_canonical_note_write_rejects_unsupported_blocks():
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Strict title", "marks": []}],
            },
            {
                "type": "table",
                "rows": [],
            }
        ],
    }

    with pytest.raises(
        BadRequestError,
        match="unsupported block type",
    ):
        build_canonical_note_write(document)
