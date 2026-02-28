"""Domain-agnostic and light domain-specific cleanup for Jina markdown."""

from __future__ import annotations

import re

NOISE_PHRASES = (
    "privacy center",
    "manage consent preferences",
    "allow all",
    "confirm my choices",
    "cookie policy",
    "vendor list",
    "do not sell or share my personal data",
    "sign up for",
    "subscribe now",
    "most popular",
    "top stories",
    "navigation drawer",
    "back to top",
    "customer service",
    "tools & features",
    "terms of use",
    "privacy notice",
    "advertiser content",
    "powered by onetrust",
)

TRACKING_HOST_PATTERNS = (
    r"analytics\.twitter\.com",
    r"t\.co/1/i/adsct",
    r"bat\.bing\.com",
    r"sync\.intentiq\.com",
    r"doubleclick\.net",
    r"googlesyndication\.com",
    r"cdn\.cookielaw\.org",
    r"onetrust\.com",
    r"cookielaw\.org",
)

NAV_SECTION_HEADERS = {
    "News",
    "Markets",
    "Opinion",
    "Customer Service",
    "Ads",
    "Tools & Features",
    "More",
    "Most Popular",
    "Top Stories",
    "Privacy Center",
}


def clean_markdown_universal(markdown: str) -> str:
    """Apply domain-agnostic cleanup heuristics to Jina markdown."""
    cleaned = _remove_tracking_artifacts(markdown)
    blocks = _split_blocks(cleaned)
    if not blocks:
        return cleaned.strip()
    filtered_blocks = [
        block
        for block in blocks
        if not _is_noise_block(block) and not _is_menu_block(block)
    ]
    if not filtered_blocks:
        filtered_blocks = blocks
    filtered_blocks = _dedupe_blocks(filtered_blocks)
    main_blocks = _select_main_article_blocks(filtered_blocks)
    cleaned = "\n\n".join(main_blocks).strip()
    cleaned = _dedupe_lines(cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def clean_markdown_verge(markdown: str) -> str:
    """Apply a minimal Verge-specific cleanup pass for persistent noise."""
    cleaned = markdown
    cleaned = re.sub(
        (
            r"(?mi)^Sign up for Verge Daily.*?$|"
            r"^close email sign up (?:banner|dialog)$|"
            r"^Let's keep it going$|^count me in!?$|^No, thanks$"
        ),
        "",
        cleaned,
    )
    cleaned = re.sub(r"(?m)^Navigation Drawer\s*$\n?", "", cleaned)
    cleaned = re.sub(r"(?m)^Comments Drawer\s*$\n?", "", cleaned)
    cleaned = re.sub(r"(?m)^Follow topics and authors.*\n?", "", cleaned)
    footer_markers = (
        "\nMost Popular\n",
        "\nTop Stories\n",
        "\nPrivacy Center\n",
        "\n© 20",
    )
    for marker in footer_markers:
        idx = cleaned.find(marker)
        if idx > 0:
            cleaned = cleaned[:idx]
            break
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def _split_blocks(markdown: str) -> list[str]:
    """Split markdown into paragraph-like blocks separated by blank lines."""
    if not markdown.strip():
        return []
    blocks = re.split(r"\n{2,}", markdown.strip())
    return [block.strip() for block in blocks if block.strip()]


def _word_count(text: str) -> int:
    """Count natural language words in text."""
    return len(re.findall(r"\b[\w'-]+\b", text))


def _link_count(text: str) -> int:
    """Count markdown links excluding images."""
    return len(re.findall(r"(?<!!)\[[^\]]+]\([^)]+\)", text))


def _list_line_count(text: str) -> int:
    """Count markdown bullet/ordered list lines."""
    return sum(
        1 for line in text.splitlines() if re.match(r"^\s*(?:[-*+]\s+|\d+\.\s+)", line)
    )


def _boilerplate_hit_count(text: str) -> int:
    """Count boilerplate phrase hits in text."""
    lowered = text.lower()
    return sum(lowered.count(phrase) for phrase in NOISE_PHRASES)


def _is_noise_block(block: str) -> bool:
    """Return True when block strongly matches boilerplate/footer content."""
    stripped = block.strip()
    lowered = stripped.lower()
    if stripped in NAV_SECTION_HEADERS:
        return True
    hit_count = _boilerplate_hit_count(lowered)
    if hit_count >= 2:
        return True
    if hit_count >= 1 and _word_count(stripped) <= 70:
        return True
    if re.match(r"^©\s*\d{4}\b", stripped):
        return True
    if "all rights reserved" in lowered and _word_count(stripped) <= 80:
        return True
    return "subscriber agreement" in lowered


def _is_menu_block(block: str) -> bool:
    """Return True when block looks like navigation/menu content."""
    words = _word_count(block)
    links = _link_count(block)
    list_lines = _list_line_count(block)
    if list_lines >= 4 and links >= 3 and words <= 140:
        return True
    if links >= 6 and words <= 120:
        return True
    return bool(words and (links / words) > 0.22 and words <= 180 and links >= 4)


def _remove_tracking_artifacts(markdown: str) -> str:
    """Remove tracker/analytics markdown links and images."""
    host_union = "|".join(TRACKING_HOST_PATTERNS)
    cleaned = re.sub(
        rf"(?m)^!?\[[^\]]*]\(https?://(?:{host_union})[^)]*\)\s*$\n?",
        "",
        markdown,
    )
    cleaned = re.sub(
        rf"!\[[^\]]*]\(https?://(?:{host_union})[^)]*\)",
        "",
        cleaned,
    )
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def _dedupe_blocks(blocks: list[str]) -> list[str]:
    """Deduplicate repeated long blocks while preserving order."""
    deduped: list[str] = []
    seen: set[str] = set()
    for block in blocks:
        normalized = re.sub(r"\s+", " ", block).strip().lower()
        is_candidate = len(normalized) >= 80
        if is_candidate and normalized in seen:
            continue
        if is_candidate:
            seen.add(normalized)
        deduped.append(block)
    return deduped


def _block_prose_score(block: str) -> float:
    """Score a block for article-likeness (higher is better prose)."""
    words = _word_count(block)
    links = _link_count(block)
    list_lines = _list_line_count(block)
    boilerplate_hits = _boilerplate_hit_count(block)
    sentence_hits = len(re.findall(r"[.!?](?:\s|$)", block))
    heading_bonus = 8 if re.search(r"(?m)^#\s+.+", block) else 0
    if re.search(r"(?m)^.+\n={3,}\s*$", block):
        heading_bonus += 8
    score = (
        words
        + min(sentence_hits * 10, 40)
        + heading_bonus
        - (links * 16)
        - (list_lines * 10)
        - (boilerplate_hits * 40)
    )
    if words >= 90:
        score += 20
    return score


def _select_main_article_blocks(blocks: list[str]) -> list[str]:
    """Keep the most prose-dense contiguous region of blocks."""
    if not blocks:
        return blocks
    if len(blocks) <= 3:
        return blocks
    scores = [_block_prose_score(block) for block in blocks]
    anchor = max(range(len(scores)), key=lambda idx: scores[idx])
    start = anchor
    end = anchor

    while start > 0:
        prev_score = scores[start - 1]
        if prev_score < -20 and scores[start] < 0:
            break
        if _is_noise_block(blocks[start - 1]):
            break
        start -= 1
    while end < len(blocks) - 1:
        next_score = scores[end + 1]
        if next_score < -20 and scores[end] < 0:
            break
        if _is_noise_block(blocks[end + 1]):
            break
        end += 1

    selected = blocks[start : end + 1]
    total_words = sum(_word_count(block) for block in blocks)
    selected_words = sum(_word_count(block) for block in selected)
    min_selected_words = min(120, max(40, int(total_words * 0.35)))
    if selected_words < min_selected_words:
        return blocks
    return selected


def _dedupe_lines(markdown: str) -> str:
    """Drop repeated boilerplate-like lines while keeping article prose."""
    if not markdown.strip():
        return markdown
    seen: set[str] = set()
    output: list[str] = []
    for raw_line in markdown.splitlines():
        line = raw_line.strip()
        normalized = re.sub(r"\s+", " ", line).lower()
        is_boilerplate_like = len(normalized) >= 50 and (
            _boilerplate_hit_count(normalized) > 0
            or "all rights reserved" in normalized
            or "privacy" in normalized
            or "cookie" in normalized
        )
        if is_boilerplate_like and normalized in seen:
            continue
        if is_boilerplate_like:
            seen.add(normalized)
        output.append(raw_line)
    return "\n".join(output).strip()
