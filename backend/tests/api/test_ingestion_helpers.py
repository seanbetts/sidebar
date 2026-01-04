import pytest

from api.exceptions import BadRequestError
from api.routers.ingestion_helpers import (
    _category_for_file,
    _extract_youtube_id,
    _filter_user_derivatives,
    _normalize_youtube_url,
    _user_message_for_error,
)


def test_normalize_youtube_url_shortlink():
    normalized = _normalize_youtube_url("youtu.be/abc123")
    assert normalized == "https://www.youtube.com/watch?v=abc123"


def test_normalize_youtube_url_invalid():
    with pytest.raises(BadRequestError):
        _normalize_youtube_url("example.com/video")


def test_extract_youtube_id_variants():
    assert _extract_youtube_id("https://youtu.be/abc123") == "abc123"
    assert _extract_youtube_id("https://www.youtube.com/watch?v=xyz789") == "xyz789"


def test_category_for_file():
    assert _category_for_file("report.csv", "text/csv") == "spreadsheets"
    assert _category_for_file("report.pdf", "application/pdf") == "documents"


def test_filter_user_derivatives():
    derivatives = [
        {"storage_key": "user-1/files/a"},
        {"storage_key": "user-2/files/b"},
    ]
    filtered = _filter_user_derivatives(derivatives, "user-1")
    assert filtered == [{"storage_key": "user-1/files/a"}]


def test_user_message_for_error():
    assert _user_message_for_error(None, "failed") is None
    assert _user_message_for_error("FILE_EMPTY", "failed") == "This file appears to be empty."
