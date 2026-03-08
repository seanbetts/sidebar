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
            {"type": "paragraph", "content": [{"text": "Hello", "marks": ["bold"]}]},
            {"type": "paragraph", "content": [{"text": "world", "marks": []}]},
        ],
    }

    assert project_plain_text_from_document(document) == "Hello\nworld"


def test_derive_title_from_first_non_empty_plain_text_line() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "paragraph", "content": [{"text": "", "marks": []}]},
            {
                "type": "paragraph",
                "content": [{"text": "# Hello world", "marks": []}],
            },
        ],
    }

    assert derive_note_title_from_document(document) == "# Hello world"


def test_derive_title_falls_back_to_new_note() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {"type": "paragraph", "content": [{"text": "   ", "marks": []}]}
        ],
    }

    assert derive_note_title_from_document(document) == DEFAULT_NOTE_TITLE
    assert derive_note_title("") == DEFAULT_NOTE_TITLE


def test_project_plain_text_rejects_unsupported_future_block_types_cleanly() -> None:
    document = {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "heading",
                "level": 1,
                "content": [{"text": "Future heading", "marks": []}],
            }
        ],
    }

    with pytest.raises(
        BadRequestError,
        match="plain_text projection currently supports paragraph blocks only",
    ):
        project_plain_text_from_document(document)
