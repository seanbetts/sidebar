from __future__ import annotations

import pytest

from api.exceptions import BadRequestError
from api.services.notes_document_types import (
    ALLOWED_BLOCK_TYPES,
    ALLOWED_INLINE_MARKS,
    NOTE_DOCUMENT_VERSION,
    validate_note_document,
)


def test_validate_note_document_accepts_version_one_title_first_documents() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [
                    {"text": "Hello", "marks": ["bold"]},
                    {"text": " world", "marks": []},
                ],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body", "marks": []}],
            },
        ],
    }

    validated = validate_note_document(document)

    assert validated == document


def test_allowed_block_types_include_future_schema_vocabulary() -> None:
    assert {
        "title",
        "paragraph",
        "heading",
        "subheading",
        "unordered_list",
        "ordered_list",
        "checklist",
        "list_item",
        "blockquote",
        "code_block",
    }.issubset(ALLOWED_BLOCK_TYPES)


def test_allowed_inline_marks_match_phase_one_scope() -> None:
    assert ALLOWED_INLINE_MARKS == {
        "bold",
        "italic",
        "underline",
        "strikethrough",
        "inline_code",
    }


def test_validate_note_document_accepts_supported_block_types() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Title", "marks": []}]},
            {"type": "heading", "content": [{"text": "Heading", "marks": []}]},
            {
                "type": "subheading",
                "content": [{"text": "Subheading", "marks": ["strikethrough"]}],
            },
            {
                "type": "unordered_list",
                "content": [{"text": "Item", "marks": ["inline_code"]}],
            },
            {"type": "ordered_list", "content": [{"text": "Item", "marks": []}]},
            {
                "type": "checklist",
                "checked": True,
                "content": [{"text": "Done", "marks": []}],
            },
            {"type": "list_item", "content": [{"text": "Nested", "marks": []}]},
            {"type": "blockquote", "content": [{"text": "Quoted", "marks": []}]},
            {"type": "code_block", "content": [{"text": "let x = 1", "marks": []}]},
        ],
    }

    validated = validate_note_document(document)

    assert validated == document


def test_validate_note_document_accepts_inline_link_payload() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [
                    {
                        "text": "Link label",
                        "marks": [],
                        "link": {"url": "https://example.com"},
                    }
                ],
            }
        ],
    }

    validated = validate_note_document(document)

    assert validated == document


def test_validate_note_document_accepts_strikethrough_inline_mark_payload() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Done", "marks": ["strikethrough"]}],
            }
        ],
    }

    validated = validate_note_document(document)

    assert validated == document


def test_validate_note_document_rejects_invalid_inline_link_payload() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [
                    {
                        "text": "Link label",
                        "marks": [],
                        "link": {"href": "https://example.com"},
                    }
                ],
            }
        ],
    }

    with pytest.raises(BadRequestError, match="Invalid note document"):
        validate_note_document(document)


def test_validate_note_document_rejects_unknown_inline_marks() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Hello", "marks": ["strike"]}],
            }
        ],
    }

    with pytest.raises(BadRequestError, match="Invalid note document"):
        validate_note_document(document)


def test_validate_note_document_promotes_legacy_paragraph_block_zero_to_title() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "paragraph",
                "content": [{"text": "Hello", "marks": []}],
            }
        ],
    }

    validated = validate_note_document(document)

    assert validated["blocks"][0]["type"] == "title"
    assert validated["blocks"][0]["content"][0]["text"] == "Hello"


def test_validate_note_document_normalizes_legacy_task_list_alias() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Title", "marks": []}],
            },
            {
                "type": "task_list",
                "content": [{"text": "Legacy item", "marks": []}],
            },
        ],
    }

    validated = validate_note_document(document)

    assert validated["blocks"][1]["type"] == "checklist"
    assert validated["blocks"][1]["checked"] is False


def test_validate_note_document_rejects_non_title_block_zero_when_not_legacy_paragraph() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "heading",
                "content": [{"text": "Heading", "marks": []}],
            }
        ],
    }

    with pytest.raises(BadRequestError, match="block 0 must be a title"):
        validate_note_document(document)
