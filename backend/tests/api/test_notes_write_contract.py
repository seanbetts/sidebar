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
    document = note_document_from_plain_text("# strict body")

    result = build_canonical_note_write(document)

    assert result.document == document
    assert result.document_version == 1
    assert result.plain_text == "# strict body"
    assert result.title == "# strict body"


def test_build_canonical_note_write_preserves_literal_hash_prefix_from_semantic_document():
    document = note_document_from_plain_text("## Literal heading markers stay literal")

    result = build_canonical_note_write(document)

    assert result.plain_text == "## Literal heading markers stay literal"
    assert result.title == "## Literal heading markers stay literal"


def test_build_canonical_note_write_rejects_non_paragraph_blocks_for_current_projection():
    document = {
        "version": 1,
        "blocks": [
            {
                "type": "heading",
                "level": 1,
                "content": [{"text": "Unsupported heading", "marks": []}],
            }
        ],
    }

    with pytest.raises(
        BadRequestError,
        match="plain_text projection currently supports paragraph blocks only",
    ):
        build_canonical_note_write(document)
