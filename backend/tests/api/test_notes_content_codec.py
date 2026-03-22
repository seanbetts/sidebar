import pytest

from api.exceptions import BadRequestError
from api.services.notes_document_types import (
    NOTE_DOCUMENT_VERSION,
    note_document_from_plain_text,
)
from api.services.notes_write_contract import (
    MAX_NOTE_PLAIN_TEXT_CHARS,
    build_canonical_note_write,
    validate_plain_text,
)


def test_build_canonical_note_write_projects_plain_text_and_title():
    document = note_document_from_plain_text("\n# Hello\nWorld")

    result = build_canonical_note_write(document)

    assert result.document == document
    assert result.document_version == NOTE_DOCUMENT_VERSION
    assert result.plain_text == "\n# Hello\nWorld"
    assert result.title == "New Note"


def test_build_canonical_note_write_accepts_inline_marks_in_paragraph_documents():
    source_document = {
        "version": 1,
        "blocks": [
            {
                "type": "paragraph",
                "content": [
                    {"text": "Marked", "marks": ["bold"]},
                    {"text": " title", "marks": ["italic"]},
                ],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body", "marks": ["underline"]}],
            },
        ],
    }

    result = build_canonical_note_write(source_document)

    assert result.document["blocks"][0]["type"] == "title"
    assert result.plain_text == "Marked title\nBody"
    assert result.title == "Marked title"


def test_validate_plain_text_requires_string():
    with pytest.raises(BadRequestError, match="plain_text required"):
        validate_plain_text(None)


def test_validate_plain_text_rejects_oversize_payload():
    with pytest.raises(BadRequestError, match="plain_text exceeds max length"):
        validate_plain_text("x" * (MAX_NOTE_PLAIN_TEXT_CHARS + 1))
