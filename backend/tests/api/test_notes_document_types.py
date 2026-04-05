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
        "divider",
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
                "children": [
                    {
                        "type": "list_item",
                        "content": [{"text": "Item", "marks": ["inline_code"]}],
                    }
                ],
            },
            {
                "type": "ordered_list",
                "children": [
                    {"type": "list_item", "content": [{"text": "Item", "marks": []}]}
                ],
            },
            {
                "type": "checklist",
                "children": [
                    {
                        "type": "list_item",
                        "checked": True,
                        "content": [{"text": "Done", "marks": []}],
                    }
                ],
            },
            {
                "type": "blockquote",
                "children": [
                    {"type": "paragraph", "content": [{"text": "Quoted", "marks": []}]}
                ],
            },
            {"type": "divider"},
            {"type": "code_block", "content": [{"text": "let x = 1", "marks": []}]},
        ],
    }

    validated = validate_note_document(document)

    assert validated == document


def test_validate_note_document_normalizes_divider_to_contentless_leaf() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Title", "marks": []}]},
            {
                "type": "divider",
                "content": [{"text": "---", "marks": []}],
                "children": [
                    {"type": "paragraph", "content": [{"text": "Ignored", "marks": []}]}
                ],
            },
        ],
    }

    validated = validate_note_document(document)

    assert validated["blocks"][1] == {"type": "divider"}


def test_validate_note_document_accepts_version_two_nested_container_blocks() -> None:
    document = {
        "version": 2,
        "blocks": [
            {"type": "title", "content": [{"text": "Title", "marks": []}]},
            {
                "type": "ordered_list",
                "children": [
                    {"type": "list_item", "content": [{"text": "First", "marks": []}]},
                    {"type": "list_item", "content": [{"text": "Second", "marks": []}]},
                ],
            },
            {
                "type": "checklist",
                "children": [
                    {
                        "type": "list_item",
                        "checked": True,
                        "content": [{"text": "Done", "marks": []}],
                    }
                ],
            },
            {
                "type": "blockquote",
                "children": [
                    {"type": "paragraph", "content": [{"text": "Quoted", "marks": []}]}
                ],
            },
            {"type": "code_block", "content": [{"text": "let x = 1", "marks": []}]},
        ],
    }

    validated = validate_note_document(document)

    assert validated == document


def test_validate_note_document_normalizes_blockquote_content_to_children() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Title", "marks": []}]},
            {
                "type": "blockquote",
                "content": [{"text": "Quoted", "marks": []}],
            },
        ],
    }

    validated = validate_note_document(document)

    assert validated["blocks"][1] == {
        "type": "blockquote",
        "children": [
            {"type": "paragraph", "content": [{"text": "Quoted", "marks": []}]}
        ],
    }


def test_validate_note_document_groups_consecutive_root_list_items() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Title", "marks": []}]},
            {"type": "list_item", "content": [{"text": "First", "marks": []}]},
            {"type": "list_item", "content": [{"text": "Second", "marks": []}]},
        ],
    }

    validated = validate_note_document(document)

    assert validated["blocks"][1] == {
        "type": "unordered_list",
        "children": [
            {"type": "list_item", "content": [{"text": "First", "marks": []}]},
            {"type": "list_item", "content": [{"text": "Second", "marks": []}]},
        ],
    }


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
        "version": 1,
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

    assert validated["version"] == NOTE_DOCUMENT_VERSION
    assert validated["blocks"][1] == {
        "type": "checklist",
        "children": [
            {
                "type": "list_item",
                "checked": False,
                "content": [{"text": "Legacy item", "marks": []}],
            }
        ],
    }


def test_validate_note_document_normalizes_heading_block_zero_to_title() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "heading",
                "content": [{"text": "Heading", "marks": []}],
            }
        ],
    }

    validated = validate_note_document(document)

    assert validated["blocks"][0]["type"] == "title"


def test_validate_note_document_normalizes_root_list_item_to_paragraph() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "list_item",
                "checked": True,
                "content": [{"text": "Orphan", "marks": []}],
            }
        ],
    }

    validated = validate_note_document(document)

    assert validated["blocks"] == [
        {
            "type": "title",
            "content": [{"text": "Orphan", "marks": []}],
        }
    ]
