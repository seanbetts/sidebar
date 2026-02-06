from api.services.website_reading_time import (
    derive_reading_time,
    extract_reading_time_from_frontmatter,
    normalize_reading_time,
)


def test_normalize_reading_time_minutes():
    assert normalize_reading_time("14 min") == "14 mins"


def test_normalize_reading_time_hours():
    assert normalize_reading_time("104 min") == "1 hr 44 mins"


def test_extract_reading_time_from_frontmatter():
    content = "---\nreading_time: '5 min'\n---\n\nBody"
    assert extract_reading_time_from_frontmatter(content) == "5 mins"


def test_derive_reading_time_without_frontmatter():
    content = "This is a short paragraph with enough words to derive reading time."
    assert derive_reading_time(content) == "1 min"
