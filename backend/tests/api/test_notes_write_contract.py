import pytest
from api.exceptions import BadRequestError
from api.services.notes_write_contract import (
    build_canonical_note_write,
    is_canonical_base64_rtf,
    plain_text_to_rtf_base64,
)


def test_build_canonical_note_write_canonicalizes_legacy_content(monkeypatch):
    monkeypatch.setenv("NOTES_STRICT_RTF_WRITES", "false")

    result = build_canonical_note_write("# Title\n\nBody", None)

    assert is_canonical_base64_rtf(result.content) is True
    assert result.plain_text == "# Title\n\nBody"


def test_build_canonical_note_write_uses_existing_plain_text_for_canonical_content(
    monkeypatch,
):
    monkeypatch.setenv("NOTES_STRICT_RTF_WRITES", "false")
    canonical_content = plain_text_to_rtf_base64("existing text")

    result = build_canonical_note_write(
        canonical_content,
        None,
        existing_plain_text="existing text",
    )

    assert result.content == canonical_content
    assert result.plain_text == "existing text"


def test_build_canonical_note_write_requires_plain_text_for_canonical_create(monkeypatch):
    monkeypatch.setenv("NOTES_STRICT_RTF_WRITES", "false")
    canonical_content = plain_text_to_rtf_base64("new text")

    with pytest.raises(BadRequestError, match="plain_text required"):
        build_canonical_note_write(canonical_content, None)


def test_build_canonical_note_write_strict_mode_rejects_legacy_content(monkeypatch):
    monkeypatch.setenv("NOTES_STRICT_RTF_WRITES", "true")

    with pytest.raises(BadRequestError, match="content must be valid Base64"):
        build_canonical_note_write("# Title\n\nBody", "# Title\n\nBody")


def test_build_canonical_note_write_strict_mode_accepts_canonical_payload(monkeypatch):
    monkeypatch.setenv("NOTES_STRICT_RTF_WRITES", "true")
    canonical_content = plain_text_to_rtf_base64("strict body")

    result = build_canonical_note_write(canonical_content, "strict body")

    assert result.content == canonical_content
    assert result.plain_text == "strict body"
