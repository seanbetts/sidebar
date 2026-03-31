"""Prompt document section helpers and typed payload contracts."""

from __future__ import annotations

from typing import TypedDict


class PromptSection(TypedDict):
    """Structured prompt section with source metadata."""

    id: str
    title: str
    source: str
    content: str
    chars: int


class PromptSectionReport(TypedDict):
    """Prompt section diagnostics without content payload."""

    id: str
    title: str
    source: str
    chars: int


class PromptDocument(TypedDict):
    """Prompt document payload with flattened text and section list."""

    text: str
    max_chars: int
    total_chars: int
    raw_total_chars: int
    constrained_total_chars: int
    truncated: bool
    truncated_by_section_limits: bool
    truncated_by_budget: bool
    sections: list[PromptSection]


class PromptDocumentReport(TypedDict):
    """Prompt diagnostics payload for one prompt document."""

    total_chars: int
    max_chars: int
    raw_total_chars: int
    constrained_total_chars: int
    truncated: bool
    truncated_by_section_limits: bool
    truncated_by_budget: bool
    sections: list[PromptSectionReport]


def truncate_text(value: str, max_chars: int) -> str:
    """Truncate a string to a maximum length."""
    if len(value) <= max_chars:
        return value
    return value[:max_chars]


def build_section(
    *,
    section_id: str,
    title: str,
    source: str,
    content: str,
) -> PromptSection:
    """Create a prompt section structure."""
    section_text = content or ""
    return {
        "id": section_id,
        "title": title,
        "source": source,
        "content": section_text,
        "chars": len(section_text),
    }


def build_prompt_document(
    sections: list[PromptSection],
    max_chars: int,
    section_char_limits: dict[str, int] | None = None,
) -> PromptDocument:
    """Build a flattened prompt document from ordered sections."""
    original_sections = normalize_sections(sections)
    normalized_sections = normalize_sections(sections)
    if section_char_limits:
        normalized_sections = apply_section_char_limits(
            normalized_sections,
            section_char_limits,
        )
    joined = join_sections(normalized_sections)
    original_joined = join_sections(original_sections)
    raw_total_chars = len(original_joined)
    constrained_total_chars = len(joined)
    truncated_by_section_limits = joined != original_joined
    truncated_by_budget = False

    if len(joined) > max_chars:
        truncated_by_budget = True
        normalized_sections = fit_sections_to_budget(
            normalized_sections,
            max_chars=max_chars,
        )
        joined = join_sections(normalized_sections)

    truncated = truncated_by_section_limits or truncated_by_budget
    text = truncate_text(joined, max_chars)
    return {
        "text": text,
        "max_chars": max_chars,
        "total_chars": len(text),
        "raw_total_chars": raw_total_chars,
        "constrained_total_chars": constrained_total_chars,
        "truncated": truncated,
        "truncated_by_section_limits": truncated_by_section_limits,
        "truncated_by_budget": truncated_by_budget,
        "sections": normalized_sections,
    }


def build_prompt_report(document: PromptDocument) -> PromptDocumentReport:
    """Build prompt diagnostics without section content."""
    return {
        "total_chars": document["total_chars"],
        "max_chars": document["max_chars"],
        "raw_total_chars": document["raw_total_chars"],
        "constrained_total_chars": document["constrained_total_chars"],
        "truncated": document["truncated"],
        "truncated_by_section_limits": document["truncated_by_section_limits"],
        "truncated_by_budget": document["truncated_by_budget"],
        "sections": [
            {
                "id": section["id"],
                "title": section["title"],
                "source": section["source"],
                "chars": section["chars"],
            }
            for section in document["sections"]
        ],
    }


def normalize_sections(sections: list[PromptSection]) -> list[PromptSection]:
    """Copy sections and recalculate char counts from current content."""
    return [
        {
            "id": section["id"],
            "title": section["title"],
            "source": section["source"],
            "content": section["content"] or "",
            "chars": len(section["content"] or ""),
        }
        for section in sections
    ]


def join_sections(sections: list[PromptSection]) -> str:
    """Join non-empty section content into the flattened document."""
    return "\n\n".join(section["content"] for section in sections if section["content"])


def apply_section_char_limits(
    sections: list[PromptSection],
    section_char_limits: dict[str, int],
) -> list[PromptSection]:
    """Apply per-section caps before fitting the full prompt budget."""
    updated = normalize_sections(sections)
    for index, section in enumerate(updated):
        max_chars = section_char_limits.get(section["id"])
        if max_chars is None or max_chars <= 0:
            continue
        content = truncate_section_content(section["content"], max_chars)
        updated[index]["content"] = content
        updated[index]["chars"] = len(content)
    return updated


def fit_sections_to_budget(
    sections: list[PromptSection],
    *,
    max_chars: int,
) -> list[PromptSection]:
    """Reduce large sections while preserving section wrappers where possible."""
    updated = normalize_sections(sections)
    shrink_order = [
        "current_open",
        "recent_activity",
        "message_context",
        "assistant_soul",
        "assistant_identity",
        "response_style",
        "context_guidance",
    ]

    while len(join_sections(updated)) > max_chars:
        overflow = len(join_sections(updated)) - max_chars
        reduced = False

        for section_id in shrink_order:
            index = next(
                (i for i, section in enumerate(updated) if section["id"] == section_id),
                None,
            )
            if index is None:
                continue
            current_content = updated[index]["content"]
            minimum_chars = minimum_section_chars(current_content)
            if len(current_content) <= minimum_chars:
                continue

            reduce_by = max(overflow, 256)
            target_chars = max(minimum_chars, len(current_content) - reduce_by)
            next_content = truncate_section_content(current_content, target_chars)
            if len(next_content) >= len(current_content):
                continue
            updated[index]["content"] = next_content
            updated[index]["chars"] = len(next_content)
            reduced = True
            if len(join_sections(updated)) <= max_chars:
                break

        if not reduced:
            break
    return updated


def minimum_section_chars(content: str) -> int:
    """Return minimum chars to keep wrapper tags intact when possible."""
    wrapped = extract_wrapped_section(content)
    if wrapped is None:
        return min(len(content), 64)
    opening_tag, _inner, closing_tag = wrapped
    return len(opening_tag) + len(closing_tag) + 2


def truncate_section_content(content: str, max_chars: int) -> str:
    """Truncate content while preserving wrapper tags for XML-like blocks."""
    if len(content) <= max_chars:
        return content
    wrapped = extract_wrapped_section(content)
    if wrapped is None:
        return truncate_text(content, max_chars)

    opening_tag, inner, closing_tag = wrapped
    overhead = len(opening_tag) + len(closing_tag) + 2
    available = max_chars - overhead
    if available <= 0:
        return truncate_text(content, max_chars)
    return f"{opening_tag}\n{inner[:available]}\n{closing_tag}"


def extract_wrapped_section(content: str) -> tuple[str, str, str] | None:
    """Extract opening tag, inner content, and closing tag for wrapped sections."""
    stripped = content.strip()
    if not stripped.startswith("<"):
        return None
    opening_end = stripped.find(">")
    if opening_end <= 0:
        return None
    opening_tag = stripped[: opening_end + 1]
    if opening_tag.startswith("</"):
        return None
    tag_name = opening_tag[1:-1].strip()
    if not tag_name:
        return None
    closing_tag = f"</{tag_name}>"
    if not stripped.endswith(closing_tag):
        return None
    inner = stripped[opening_end + 1 : -len(closing_tag)]
    return opening_tag, inner, closing_tag
