"""Semantic note document validation and projection helpers."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from api.exceptions import BadRequestError

NOTE_DOCUMENT_VERSION = 1

ALLOWED_BLOCK_TYPES = {
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
PHASE_ONE_SUPPORTED_BLOCK_TYPES = {"paragraph"}
ALLOWED_INLINE_MARKS = {"bold", "italic", "underline"}


def _invalid_document(message: str) -> BadRequestError:
    """Return a consistent semantic document validation error."""
    return BadRequestError(f"Invalid note document: {message}")


def document_version(document: dict[str, Any]) -> int:
    """Return the declared document version."""
    version = document.get("version")
    if not isinstance(version, int):
        raise _invalid_document("version must be an integer")
    return version


def validate_note_document(document: Any) -> dict[str, Any]:
    """Validate the semantic note document shape and return a copy."""
    if not isinstance(document, dict):
        raise _invalid_document("document must be an object")

    normalized = deepcopy(document)
    version = document_version(normalized)
    if version != NOTE_DOCUMENT_VERSION:
        raise _invalid_document(f"unsupported version {version}")

    blocks = normalized.get("blocks")
    if not isinstance(blocks, list):
        raise _invalid_document("blocks must be a list")

    for index, block in enumerate(blocks):
        _validate_block(block, index)

    return normalized


def project_plain_text_from_document(document: Any) -> str:
    """Project deterministic plain text from a validated semantic document."""
    validated = validate_note_document(document)
    projected_blocks: list[str] = []

    for index, block in enumerate(validated["blocks"]):
        block_type = block["type"]
        if block_type not in PHASE_ONE_SUPPORTED_BLOCK_TYPES:
            raise _invalid_document(
                "plain_text projection currently supports paragraph blocks only"
            )
        projected_blocks.append(_project_paragraph_block(block, index))

    return "\n".join(projected_blocks)


def note_document_from_plain_text(plain_text: Any) -> dict[str, Any]:
    """Build a minimal semantic document from plain text."""
    if not isinstance(plain_text, str):
        raise _invalid_document("plain_text source must be a string")
    return {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "paragraph",
                "content": [{"text": plain_text, "marks": []}],
            }
        ],
    }


def _validate_block(block: Any, index: int) -> None:
    """Validate one semantic block."""
    if not isinstance(block, dict):
        raise _invalid_document(f"block {index} must be an object")

    block_type = block.get("type")
    if not isinstance(block_type, str) or block_type not in ALLOWED_BLOCK_TYPES:
        raise _invalid_document(f"block {index} has an invalid type")

    if block_type == "paragraph":
        _validate_paragraph_block(block, index)


def _validate_paragraph_block(block: dict[str, Any], index: int) -> None:
    """Validate a paragraph block."""
    content = block.get("content")
    if not isinstance(content, list):
        raise _invalid_document(f"block {index} content must be a list")

    for segment_index, segment in enumerate(content):
        _validate_inline_segment(
            segment,
            block_index=index,
            segment_index=segment_index,
        )


def _validate_inline_segment(
    segment: Any, *, block_index: int, segment_index: int
) -> None:
    """Validate one inline semantic segment."""
    if not isinstance(segment, dict):
        raise _invalid_document(
            f"block {block_index} segment {segment_index} must be an object"
        )

    text = segment.get("text")
    if not isinstance(text, str):
        raise _invalid_document(
            f"block {block_index} segment {segment_index} text must be a string"
        )

    marks = segment.get("marks")
    if not isinstance(marks, list):
        raise _invalid_document(
            f"block {block_index} segment {segment_index} marks must be a list"
        )
    if any(not isinstance(mark, str) for mark in marks):
        raise _invalid_document(
            f"block {block_index} segment {segment_index} marks must be strings"
        )

    invalid_marks = sorted(set(marks) - ALLOWED_INLINE_MARKS)
    if invalid_marks:
        raise _invalid_document(
            f"block {block_index} segment {segment_index} has unsupported marks"
        )


def _project_paragraph_block(block: dict[str, Any], index: int) -> str:
    """Project one paragraph block into plain text."""
    content = block["content"]
    if not isinstance(content, list):
        raise _invalid_document(f"block {index} content must be a list")
    return "".join(str(segment["text"]) for segment in content)
