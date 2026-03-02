import pytest
from api.exceptions import BadRequestError
from api.services.notes_write_contract import (
    build_canonical_note_write,
    plain_text_to_rtf_base64,
)


def test_build_canonical_note_write_requires_plain_text():
    canonical_content = plain_text_to_rtf_base64("new text")

    with pytest.raises(BadRequestError, match="plain_text required"):
        build_canonical_note_write(canonical_content, None)


def test_build_canonical_note_write_rejects_non_canonical_content():
    with pytest.raises(BadRequestError, match="content must be valid Base64"):
        build_canonical_note_write("# Title\n\nBody", "# Title\n\nBody")


def test_build_canonical_note_write_accepts_canonical_payload():
    canonical_content = plain_text_to_rtf_base64("strict body")

    result = build_canonical_note_write(canonical_content, "strict body")

    assert result.content == canonical_content
    assert result.plain_text == "strict body"
