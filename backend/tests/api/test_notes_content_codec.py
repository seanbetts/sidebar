import pytest

from api.exceptions import BadRequestError
from api.services.notes_content_codec import (
    canonical_note_content_from_plain_text,
    note_plain_text_from_record,
)
from api.services.notes_write_contract import is_canonical_base64_rtf


def test_canonical_note_content_from_plain_text_returns_canonical_pair():
    result = canonical_note_content_from_plain_text("Hello\nWorld")

    assert result.plain_text == "Hello\nWorld"
    assert is_canonical_base64_rtf(result.content) is True


def test_canonical_note_content_from_plain_text_requires_string():
    with pytest.raises(BadRequestError, match="plain_text required"):
        canonical_note_content_from_plain_text(None)


def test_note_plain_text_from_record_prefers_metadata():
    resolved = note_plain_text_from_record(
        "raw-content",
        {"plain_text": "metadata text"},
    )
    assert resolved == "metadata text"


def test_note_plain_text_from_record_missing_metadata_returns_empty_string():
    resolved = note_plain_text_from_record("raw-content", {})
    assert resolved == ""
