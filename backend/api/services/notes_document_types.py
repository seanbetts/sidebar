"""Semantic note document validation and projection helpers."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from api.exceptions import BadRequestError

NOTE_DOCUMENT_VERSION = 1

ALLOWED_BLOCK_TYPES = {
    "title",
    "paragraph",
    "heading",
    "subheading",
    "unordered_list",
    "ordered_list",
    "task_list",
    "checklist",
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
SUPPORTED_BLOCK_TYPES = {
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
}
ALLOWED_INLINE_MARKS = {"bold", "italic", "underline", "strikethrough", "inline_code"}
LEGACY_BLOCK_TYPE_ALIASES = {
    "task_list": "checklist",
}
TITLE_NORMALIZABLE_BLOCK_TYPES = {
    "paragraph",
    "heading",
    "subheading",
}


def _invalid_document(message: str) -> BadRequestError:
    """Return a consistent semantic document validation error."""
    return BadRequestError(f"Invalid note document: {message}")


def document_version(document: dict[str, Any]) -> int:
    """Return the declared document version."""
    version = document.get("version")
    if not isinstance(version, int):
        raise _invalid_document("version must be an integer")
    return version


def validate_note_document(
    document: Any, *, require_title_block: bool = True
) -> dict[str, Any]:
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
        _normalize_legacy_block_aliases(block)
        _validate_block(block, index)

    if require_title_block and blocks:
        if blocks[0]["type"] in TITLE_NORMALIZABLE_BLOCK_TYPES:
            blocks[0]["type"] = "title"
        elif blocks[0]["type"] != "title":
            raise _invalid_document("block 0 must be a title")

    return normalized


def project_plain_text_from_document(document: Any) -> str:
    """Project deterministic plain text from a validated semantic document."""
    validated = validate_note_document(document)
    projected_blocks: list[str] = []
    ordered_index = 0

    for index, block in enumerate(validated["blocks"]):
        block_type = block["type"]
        projected = _project_block(block, index=index, ordered_index=ordered_index)
        projected_blocks.append(projected)
        if block_type == "ordered_list":
            ordered_index += 1
        else:
            ordered_index = 0

    return "\n".join(projected_blocks)


def note_document_from_plain_text(plain_text: Any) -> dict[str, Any]:
    """Build a minimal semantic document from plain text."""
    if not isinstance(plain_text, str):
        raise _invalid_document("plain_text source must be a string")
    lines = plain_text.split("\n")
    blocks: list[dict[str, Any]] = [
        {
            "type": "title",
            "content": [{"text": lines[0] if lines else "", "marks": []}],
        }
    ]
    blocks.extend(
        {
            "type": "paragraph",
            "content": [{"text": line, "marks": []}],
        }
        for line in lines[1:]
    )
    return {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": blocks,
    }


def _validate_block(block: Any, index: int) -> None:
    """Validate one semantic block."""
    if not isinstance(block, dict):
        raise _invalid_document(f"block {index} must be an object")

    block_type = block.get("type")
    if not isinstance(block_type, str) or block_type not in ALLOWED_BLOCK_TYPES:
        raise _invalid_document(f"block {index} has an invalid type")

    if block_type in SUPPORTED_BLOCK_TYPES:
        _validate_supported_block(block, index)


def _normalize_legacy_block_aliases(block: Any) -> None:
    """Normalize legacy block aliases in-place before validation."""
    if not isinstance(block, dict):
        return
    block_type = block.get("type")
    if not isinstance(block_type, str):
        return
    normalized_type = LEGACY_BLOCK_TYPE_ALIASES.get(block_type)
    if normalized_type is not None:
        block["type"] = normalized_type
        if normalized_type == "checklist" and "checked" not in block:
            block["checked"] = False


def _validate_supported_block(block: dict[str, Any], index: int) -> None:
    """Validate one supported semantic block."""
    content = block.get("content")
    if not isinstance(content, list):
        raise _invalid_document(f"block {index} content must be a list")

    if block["type"] == "checklist":
        checked = block.get("checked")
        if not isinstance(checked, bool):
            raise _invalid_document(f"block {index} checked must be a boolean")

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

    if "link" in segment:
        link = segment["link"]
        if not isinstance(link, dict):
            raise _invalid_document(
                f"block {block_index} segment {segment_index} link must be an object"
            )
        link_url = link.get("url")
        if not isinstance(link_url, str) or not link_url.strip():
            raise _invalid_document(
                f"block {block_index} segment {segment_index} link url must be a string"
            )


def _project_block(block: dict[str, Any], *, index: int, ordered_index: int) -> str:
    """Project one semantic block into deterministic plain text."""
    block_type = block["type"]
    if block_type == "title":
        return _project_textual_block(block, index=index)
    if block_type == "paragraph":
        return _project_textual_block(block, index=index)
    if block_type == "heading":
        return _project_textual_block(block, index=index)
    if block_type == "subheading":
        return _project_textual_block(block, index=index)
    if block_type == "list_item":
        return _project_textual_block(block, index=index)
    if block_type == "unordered_list":
        return f"- {_project_textual_block(block, index=index)}"
    if block_type == "ordered_list":
        return f"{ordered_index + 1}. {_project_textual_block(block, index=index)}"
    if block_type == "checklist":
        marker = "x" if block["checked"] else " "
        return f"- [{marker}] {_project_textual_block(block, index=index)}"
    if block_type == "blockquote":
        return f"> {_project_textual_block(block, index=index)}"
    if block_type == "code_block":
        return _project_textual_block(block, index=index)
    raise _invalid_document(
        f"unsupported block type for plain_text projection: {block_type}"
    )


def _project_textual_block(block: dict[str, Any], *, index: int) -> str:
    """Project a text-bearing block's inline content."""
    content = block["content"]
    if not isinstance(content, list):
        raise _invalid_document(f"block {index} content must be a list")
    return "".join(
        _project_inline_segment_text(segment, block_index=index) for segment in content
    )


def _project_inline_segment_text(segment: Any, *, block_index: int) -> str:
    """Project one inline segment to visible plain text."""
    if not isinstance(segment, dict):
        raise _invalid_document(f"block {block_index} segment must be an object")
    text = segment.get("text")
    if not isinstance(text, str):
        raise _invalid_document(f"block {block_index} segment text must be a string")
    if text:
        return text
    link = segment.get("link")
    if isinstance(link, dict):
        link_url = link.get("url")
        if isinstance(link_url, str):
            return link_url
    return ""
