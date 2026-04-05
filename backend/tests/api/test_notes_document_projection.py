from __future__ import annotations

import pytest

from api.exceptions import BadRequestError
from api.services.notes_document_types import (
    NOTE_DOCUMENT_VERSION,
    project_plain_text_from_document,
)
from api.services.notes_title import (
    DEFAULT_NOTE_TITLE,
    derive_note_title,
    derive_note_title_from_document,
)


def test_project_plain_text_from_paragraph_document() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Hello", "marks": ["bold"]}]},
            {"type": "paragraph", "content": [{"text": "world", "marks": []}]},
        ],
    }

    assert project_plain_text_from_document(document) == "Hello\nworld"


def test_derive_title_from_legacy_paragraph_block_zero_promotes_to_title() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "paragraph", "content": [{"text": "Legacy title", "marks": []}]},
            {
                "type": "paragraph",
                "content": [{"text": "Body", "marks": []}],
            },
        ],
    }

    assert derive_note_title_from_document(document) == "Legacy title"


def test_derive_title_falls_back_to_new_note() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "   ", "marks": []}]}
        ],
    }

    assert derive_note_title_from_document(document) == DEFAULT_NOTE_TITLE
    assert derive_note_title("") == DEFAULT_NOTE_TITLE


def test_derive_title_normalizes_heading_block_zero_to_title() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "heading", "content": [{"text": "Heading", "marks": []}]}
        ],
    }

    assert derive_note_title_from_document(document) == "Heading"


def test_project_plain_text_rejects_unsupported_block_types_cleanly() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Hello", "marks": []}]},
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
        project_plain_text_from_document(document)


def test_project_plain_text_handles_supported_rich_block_types_deterministically() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Release notes", "marks": []}]},
            {"type": "heading", "content": [{"text": "Today", "marks": []}]},
            {"type": "subheading", "content": [{"text": "Status", "marks": []}]},
            {
                "type": "unordered_list",
                "children": [
                    {
                        "type": "list_item",
                        "content": [{"text": "Ship schema", "marks": []}],
                    }
                ],
            },
            {
                "type": "ordered_list",
                "children": [
                    {
                        "type": "list_item",
                        "content": [{"text": "Run tests", "marks": []}],
                    },
                    {
                        "type": "list_item",
                        "content": [{"text": "Review output", "marks": []}],
                    },
                ],
            },
            {
                "type": "checklist",
                "children": [
                    {
                        "type": "list_item",
                        "checked": True,
                        "content": [{"text": "Done item", "marks": []}],
                    },
                    {
                        "type": "list_item",
                        "checked": False,
                        "content": [{"text": "Open item", "marks": []}],
                    },
                ],
            },
            {
                "type": "blockquote",
                "children": [
                    {
                        "type": "paragraph",
                        "content": [{"text": "Quoted line", "marks": []}],
                    }
                ],
            },
            {"type": "divider"},
            {
                "type": "code_block",
                "content": [{"text": "line 1\nline 2", "marks": []}],
            },
        ],
    }

    assert project_plain_text_from_document(document) == (
        "Release notes\n"
        "Today\n"
        "Status\n"
        "- Ship schema\n"
        "1. Run tests\n"
        "2. Review output\n"
        "- [x] Done item\n"
        "- [ ] Open item\n"
        "> Quoted line\n"
        "\n"
        "line 1\nline 2"
    )


def test_project_plain_text_projects_divider_as_blank_separator() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "title", "content": [{"text": "Weekly plan", "marks": []}]},
            {"type": "paragraph", "content": [{"text": "Top priorities", "marks": []}]},
            {"type": "divider"},
            {"type": "paragraph", "content": [{"text": "Backlog review", "marks": []}]},
        ],
    }

    assert project_plain_text_from_document(document) == (
        "Weekly plan\n"
        "Top priorities\n"
        "\n"
        "Backlog review"
    )


def test_project_plain_text_uses_link_label_or_url_fallback() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [
                    {"text": "Read ", "marks": []},
                    {
                        "text": "Docs",
                        "marks": [],
                        "link": {"url": "https://example.com/docs"},
                    },
                ],
            },
            {
                "type": "paragraph",
                "content": [
                    {
                        "text": "",
                        "marks": [],
                        "link": {"url": "https://example.com/fallback"},
                    }
                ],
            },
        ],
    }

    assert project_plain_text_from_document(document) == (
        "Read Docs\nhttps://example.com/fallback"
    )


def test_project_plain_text_preserves_inline_code_visibility_and_code_block_newlines() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "Snippet", "marks": ["inline_code"]}],
            },
            {
                "type": "code_block",
                "content": [{"text": "let x = 1\nprint(x)", "marks": []}],
            },
        ],
    }

    assert project_plain_text_from_document(document) == "Snippet\nlet x = 1\nprint(x)"


def test_derive_title_from_block_zero_title() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "title",
                "content": [{"text": "  Semantic Title  ", "marks": []}],
            },
            {
                "type": "paragraph",
                "content": [{"text": "Body line", "marks": []}],
            },
        ],
    }

    assert derive_note_title_from_document(document) == "Semantic Title"
