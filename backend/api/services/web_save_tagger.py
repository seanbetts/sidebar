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


def compute_word_count(markdown_text: str) -> int:
    """Estimate word count from markdown."""
    words = re.findall(r"\b\w+\b", markdown_text)
    return len(words)


def calculate_reading_time(word_count: int, *, wpm: int = 200) -> str:
    """Calculate reading time string."""
    if word_count <= 0:
        return "1 min"
    minutes = max(1, round(word_count / wpm))
    return f"{minutes} min"


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
