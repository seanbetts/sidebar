"""Auto-tagging helpers for web-save parsing."""

from __future__ import annotations

import re
from collections import Counter

STOP_WORDS = {
    "the",
    "a",
    "an",
    "and",
    "or",
    "but",
    "in",
    "on",
    "at",
    "of",
    "to",
    "for",
    "with",
    "by",
    "from",
    "as",
    "is",
    "are",
    "was",
    "were",
    "be",
    "this",
    "that",
    "these",
    "those",
    "it",
    "its",
    "you",
    "your",
    "we",
    "our",
    "they",
    "their",
}

DOMAIN_CATEGORIES = {
    "github.com": ["programming", "code"],
    "stackoverflow.com": ["programming", "qa"],
    "medium.com": ["blog"],
    "dev.to": ["programming", "tutorial"],
    "news.ycombinator.com": ["news", "tech"],
}

PROGRAMMING_KEYWORDS = {
    "python",
    "javascript",
    "typescript",
    "react",
    "vue",
    "svelte",
    "api",
    "database",
    "docker",
    "kubernetes",
    "aws",
    "ai",
    "machine learning",
    "data science",
}


def _strip_frontmatter(text: str) -> str:
    """Remove YAML frontmatter from markdown."""
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[end + 4 :].lstrip()
    return text


def _strip_code_blocks(text: str) -> str:
    """Remove fenced code blocks from markdown."""
    # Remove ```...``` blocks
    text = re.sub(r"```[\s\S]*?```", "", text)
    # Remove indented code blocks (4+ spaces at line start)
    text = re.sub(r"(?m)^(?: {4,}|\t+)[^\n]*\n?", "", text)
    return text


def _clean_markdown_for_counting(text: str) -> str:
    """Clean markdown syntax for accurate word counting."""
    # Replace markdown links [text](url) with just text
    text = re.sub(r"\[([^\]]*)\]\([^)]+\)", r"\1", text)
    # Remove image markdown ![alt](url) entirely (we count images separately)
    text = re.sub(r"!\[[^\]]*\]\([^)]+\)", "", text)
    # Remove standalone URLs
    text = re.sub(r"https?://[^\s\)>]+", "", text)
    # Remove HTML tags
    text = re.sub(r"<[^>]+>", "", text)
    return text


def count_images(markdown_text: str) -> int:
    """Count images in markdown."""
    return len(re.findall(r"!\[[^\]]*\]\([^)]+\)", markdown_text))


def compute_word_count(markdown_text: str) -> int:
    """Estimate word count from markdown, excluding non-content elements."""
    text = _strip_frontmatter(markdown_text)
    text = _strip_code_blocks(text)
    text = _clean_markdown_for_counting(text)
    words = re.findall(r"\b\w+\b", text)
    return len(words)


def format_reading_time(total_minutes: int) -> str:
    """Format minutes into a readable string with proper pluralization."""
    if total_minutes <= 0:
        total_minutes = 1
    if total_minutes >= 60:
        hours = total_minutes // 60
        remaining = total_minutes % 60
        hr_label = "hr" if hours == 1 else "hrs"
        if remaining == 0:
            return f"{hours} {hr_label}"
        min_label = "min" if remaining == 1 else "mins"
        return f"{hours} {hr_label} {remaining} {min_label}"
    min_label = "min" if total_minutes == 1 else "mins"
    return f"{total_minutes} {min_label}"


def calculate_reading_time(
    word_count: int, *, image_count: int = 0, wpm: int = 200
) -> str:
    """Calculate reading time string.

    Uses 200 WPM for prose and adds ~12 seconds per image.
    Returns "X hrs Y mins" for times over 60 minutes.
    """
    if word_count <= 0 and image_count <= 0:
        return "1 min"
    # Base time from words
    minutes = word_count / wpm
    # Add time for images (~12 seconds each, following Medium's approach)
    minutes += image_count * 0.2
    return format_reading_time(max(1, round(minutes)))


def extract_tags(
    content: str, domain: str, title: str, *, max_tags: int = 5
) -> list[str]:
    """Extract tags from content using simple heuristics."""
    tags: list[str] = []

    domain_tags = DOMAIN_CATEGORIES.get(domain.lower())
    if domain_tags:
        tags.extend(domain_tags)

    content_lower = content.lower()
    title_lower = title.lower()
    for keyword in PROGRAMMING_KEYWORDS:
        if keyword in content_lower or keyword in title_lower:
            tags.append(keyword)

    if len(tags) < max_tags:
        words = re.findall(r"\b\w{4,}\b", content_lower)
        filtered = [word for word in words if word not in STOP_WORDS]
        common = Counter(filtered).most_common(10)
        tags.extend([word for word, count in common if count > 3])

    deduped = []
    seen = set()
    for tag in tags:
        if tag in seen:
            continue
        seen.add(tag)
        deduped.append(tag)
    return deduped[:max_tags]
