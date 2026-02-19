from api.routers import websites_helpers


def test_resolve_jina_reading_time_prefers_metadata():
    reading_time = websites_helpers._resolve_jina_reading_time(
        metadata={"reading_time": "104 min"},
        source="https://www.youtube.com/watch?v=abc123xyzAA",
        fallback_url="https://www.youtube.com/watch?v=abc123xyzAA",
    )

    assert reading_time == "1 hr 44 mins"


def test_resolve_jina_reading_time_uses_youtube_duration(monkeypatch):
    monkeypatch.setattr(
        websites_helpers,
        "fetch_youtube_duration_seconds",
        lambda _url: 214,
    )

    reading_time = websites_helpers._resolve_jina_reading_time(
        metadata={"reading_time": None},
        source="https://www.youtube.com/watch?v=abc123xyzAA",
        fallback_url="https://example.com/post",
    )

    assert reading_time == "4 mins"
