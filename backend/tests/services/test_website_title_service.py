"""Tests for website title normalization and fallback behavior."""

from api.services import website_title_service


def test_resolve_website_title_strips_youtube_suffix():
    title = website_title_service.resolve_website_title(
        "OpenAI Super Bowl 2026 | Codex | You Can Just Build Things - YouTube",
        url="https://www.youtube.com/watch?v=aCN9iCXNJqQ",
        allow_network=False,
    )

    assert title == "OpenAI Super Bowl 2026 | Codex | You Can Just Build Things"


def test_resolve_website_title_uses_html_meta_for_placeholder():
    raw_html = """
    <html>
      <head>
        <title>- YouTube</title>
        <meta property="og:title" content="Recovered YouTube Title">
      </head>
      <body><article><p>Body</p></article></body>
    </html>
    """

    title = website_title_service.resolve_website_title(
        "- YouTube",
        url="https://www.youtube.com/watch?v=abc123xyzAA",
        raw_html=raw_html,
        allow_network=False,
    )

    assert title == "Recovered YouTube Title"


def test_resolve_website_title_falls_back_to_oembed(monkeypatch):
    class FakeResponse:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, str]:
            return {"title": "Recovered from oEmbed - YouTube"}

    def fake_get(url: str, headers: dict[str, str], timeout: int):  # noqa: ARG001
        assert "youtube.com/oembed" in url
        assert "abc123xyzAA" in url
        return FakeResponse()

    monkeypatch.setattr(website_title_service.requests, "get", fake_get)

    title = website_title_service.resolve_website_title(
        "- YouTube",
        url="https://www.youtube.com/watch?v=abc123xyzAA",
        allow_network=True,
    )

    assert title == "Recovered from oEmbed"
