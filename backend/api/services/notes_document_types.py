"""Semantic note document validation and projection helpers."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from api.exceptions import BadRequestError

NOTE_DOCUMENT_VERSION = 2

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
ROOT_CONTAINER_TYPES = {"ordered_list", "unordered_list", "checklist", "blockquote"}
LIST_CONTAINER_TYPES = {"ordered_list", "unordered_list", "checklist"}
BLOCKQUOTE_CHILD_TYPES = {
    "paragraph",
    "heading",
    "subheading",
    "ordered_list",
    "unordered_list",
    "checklist",
    "code_block",
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
    """Validate the semantic note document shape and return canonical v2."""
    if not isinstance(document, dict):
        raise _invalid_document("document must be an object")

    normalized = deepcopy(document)
    version = document_version(normalized)
    if version not in {1, NOTE_DOCUMENT_VERSION}:
        raise _invalid_document(f"unsupported version {version}")

    blocks = normalized.get("blocks")
    if not isinstance(blocks, list):
        raise _invalid_document("blocks must be a list")

    if version == 1:
        blocks = [
            _adapt_version_one_block(block, index=index)
            for index, block in enumerate(blocks)
        ]

    canonical_blocks = []
    for index, block in enumerate(blocks):
        normalized_block = _normalize_block(block, index=index, parent_type=None)
        if normalized_block is not None:
            canonical_blocks.append(normalized_block)

    if require_title_block and canonical_blocks:
        if canonical_blocks[0]["type"] in TITLE_NORMALIZABLE_BLOCK_TYPES:
            canonical_blocks[0] = {
                "type": "title",
                "content": canonical_blocks[0].get("content", []),
            }
        elif canonical_blocks[0]["type"] != "title":
            raise _invalid_document("block 0 must be a title")

    return {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": canonical_blocks,
    }


def project_plain_text_from_document(document: Any) -> str:
    """Project deterministic plain text from a validated semantic document."""
    validated = validate_note_document(document)
    return "\n".join(_project_lines(validated["blocks"]))


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


def _adapt_version_one_block(block: Any, *, index: int) -> dict[str, Any]:
    """Convert legacy flat v1 blocks into the nearest v2 shape."""
    if not isinstance(block, dict):
        raise _invalid_document(f"block {index} must be an object")

    normalized = deepcopy(block)
    _normalize_legacy_block_aliases(normalized)
    block_type = normalized.get("type")
    if not isinstance(block_type, str) or block_type not in ALLOWED_BLOCK_TYPES:
        raise _invalid_document(f"block {index} has an invalid type")

    if block_type in {"ordered_list", "unordered_list"}:
        return {
            "type": block_type,
            "children": [
                {
                    "type": "list_item",
                    "content": normalized.get("content", []),
                }
            ],
        }
    if block_type == "checklist":
        return {
            "type": "checklist",
            "children": [
                {
                    "type": "list_item",
                    "checked": bool(normalized.get("checked")),
                    "content": normalized.get("content", []),
                }
            ],
        }
    if block_type == "blockquote":
        return {
            "type": "blockquote",
            "children": [
                {
                    "type": "paragraph",
                    "content": normalized.get("content", []),
                }
            ],
        }
    return normalized


def _normalize_block(
    block: Any,
    *,
    index: int,
    parent_type: str | None,
) -> dict[str, Any] | None:
    """Normalize one block into canonical v2 form."""
    if not isinstance(block, dict):
        raise _invalid_document(f"block {index} must be an object")

    normalized = deepcopy(block)
    _normalize_legacy_block_aliases(normalized)
    block_type = normalized.get("type")
    if not isinstance(block_type, str) or block_type not in ALLOWED_BLOCK_TYPES:
        raise _invalid_document(f"block {index} has an invalid type")

    if block_type in LIST_CONTAINER_TYPES:
        children = normalized.get("children")
        if not isinstance(children, list):
            raise _invalid_document(f"block {index} children must be a list")
        normalized_children = []
        for child_index, child in enumerate(children):
            normalized_child = _normalize_block(
                child,
                index=child_index,
                parent_type=block_type,
            )
            if normalized_child is not None and normalized_child["type"] == "list_item":
                normalized_children.append(normalized_child)
        if not normalized_children:
            return None
        return {
            "type": block_type,
            "children": normalized_children,
        }

    if block_type == "blockquote":
        children = normalized.get("children")
        if not isinstance(children, list):
            raise _invalid_document(f"block {index} children must be a list")
        normalized_children = []
        for child_index, child in enumerate(children):
            normalized_child = _normalize_block(
                child,
                index=child_index,
                parent_type=block_type,
            )
            if normalized_child is None:
                continue
            if normalized_child["type"] in BLOCKQUOTE_CHILD_TYPES:
                normalized_children.append(normalized_child)
        if not normalized_children:
            return None
        return {
            "type": "blockquote",
            "children": normalized_children,
        }

    _validate_supported_leaf_block(normalized, index, parent_type=parent_type)

    if block_type == "list_item":
        if parent_type not in LIST_CONTAINER_TYPES:
            return {
                "type": "paragraph",
                "content": normalized["content"],
            }
        canonical = {
            "type": "list_item",
            "content": normalized["content"],
        }
        if parent_type == "checklist":
            canonical["checked"] = bool(normalized.get("checked"))
        return canonical

    if block_type not in SUPPORTED_BLOCK_TYPES:
        return {"type": block_type}

    canonical = {
        "type": block_type,
        "content": normalized["content"],
    }
    return canonical


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


def _validate_supported_leaf_block(
    block: dict[str, Any],
    index: int,
    *,
    parent_type: str | None,
) -> None:
    """Validate supported leaf blocks and their inline segments."""
    block_type = block["type"]
    if block_type not in SUPPORTED_BLOCK_TYPES:
        return

    content = block.get("content")
    if not isinstance(content, list):
        raise _invalid_document(f"block {index} content must be a list")

    if block_type == "list_item":
        checked = block.get("checked")
        if parent_type == "checklist":
            if not isinstance(checked, bool):
                raise _invalid_document(f"block {index} checked must be a boolean")
        elif checked is not None:
            block.pop("checked", None)

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


def _project_lines(
    blocks: list[dict[str, Any]], *, quote_prefix: str = ""
) -> list[str]:
    """Project canonical blocks into visible plain-text lines."""
    lines: list[str] = []
    for block in blocks:
        block_type = block["type"]
        if block_type in {
            "title",
            "paragraph",
            "heading",
            "subheading",
            "code_block",
        }:
            lines.extend(
                _prefixed_lines(_project_textual_block(block), prefix=quote_prefix)
            )
        elif block_type == "ordered_list":
            for item_index, child in enumerate(block.get("children", []), start=1):
                lines.extend(
                    _prefixed_lines(
                        _project_textual_block(child),
                        prefix=f"{quote_prefix}{item_index}. ",
                    )
                )
        elif block_type == "unordered_list":
            for child in block.get("children", []):
                lines.extend(
                    _prefixed_lines(
                        _project_textual_block(child), prefix=f"{quote_prefix}- "
                    )
                )
        elif block_type == "checklist":
            for child in block.get("children", []):
                marker = "x" if child.get("checked") else " "
                lines.extend(
                    _prefixed_lines(
                        _project_textual_block(child),
                        prefix=f"{quote_prefix}- [{marker}] ",
                    )
                )
        elif block_type == "blockquote":
            lines.extend(
                _project_lines(
                    block.get("children", []), quote_prefix=f"{quote_prefix}> "
                )
            )
        else:
            raise _invalid_document(
                f"unsupported block type for plain_text projection: {block_type}"
            )
    return lines


def _project_textual_block(block: dict[str, Any]) -> str:
    """Project a text-bearing block's inline content."""
    content = block["content"]
    if not isinstance(content, list):
        raise _invalid_document("block content must be a list")
    return "".join(_project_inline_segment_text(segment) for segment in content)


def _project_inline_segment_text(segment: Any) -> str:
    """Project one inline segment to visible plain text."""
    if not isinstance(segment, dict):
        raise _invalid_document("block segment must be an object")
    text = segment.get("text")
    if not isinstance(text, str):
        raise _invalid_document("block segment text must be a string")
    if text:
        return text
    link = segment.get("link")
    if isinstance(link, dict):
        link_url = link.get("url")
        if isinstance(link_url, str):
            return link_url
    return ""


def _prefixed_lines(content: str, *, prefix: str) -> list[str]:
    """Apply a visible prefix to every line in a block."""
    lines = content.split("\n")
    return [f"{prefix}{line}" for line in lines]
