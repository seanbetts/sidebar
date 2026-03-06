from __future__ import annotations

import pytest

from api.exceptions import BadRequestError
from api.services.notes_document_types import (
    ALLOWED_BLOCK_TYPES,
    ALLOWED_INLINE_MARKS,
    NOTE_DOCUMENT_VERSION,
    validate_note_document,
)


def test_validate_note_document_accepts_version_one_paragraphs() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "paragraph",
                "content": [
                    {"text": "Hello", "marks": ["bold"]},
                    {"text": " world", "marks": []},
                ],
            }
        ],
    }

    validated = validate_note_document(document)

    assert validated == document


def test_allowed_block_types_include_future_schema_vocabulary() -> None:
    assert ALLOWED_BLOCK_TYPES == {
        "paragraph",
        "heading",
        "unordered_list",
        "ordered_list",
        "task_list",
        "list_item",
        "blockquote",
        "code_block",
        "table",
        "table_row",
        "table_cell",
        "media",
        "caption",
        "html_block",
    }


def test_allowed_inline_marks_match_phase_one_scope() -> None:
    assert ALLOWED_INLINE_MARKS == {"bold", "italic", "underline"}


def test_validate_note_document_rejects_unknown_inline_marks() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "paragraph",
                "content": [{"text": "Hello", "marks": ["strike"]}],
            }
        ],
    }

    with pytest.raises(BadRequestError, match="Invalid note document"):
        validate_note_document(document)
