"""Tests for the web-save local parser."""
from datetime import datetime, timezone

from api.services import web_save_parser


def test_parse_url_local_builds_frontmatter(monkeypatch):
    html = """
    <html>
      <head>
        <title>Example Article</title>
        <meta name="author" content="Jane Doe"/>
        <meta property="article:published_time" content="2025-01-01T12:00:00Z"/>
        <link rel="canonical" href="https://example.com/article"/>
      </head>
      <body>
        <article>
          <h1>Example Article</h1>
          <p>First paragraph with some words.</p>
          <p>Second paragraph with more words.</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article?utm=ignored"

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")

    assert parsed.title == "Example Article"
    assert parsed.source == "https://example.com/article"
    assert parsed.published_at == datetime(2025, 1, 1, 12, 0, tzinfo=timezone.utc)
    assert parsed.content.startswith("---\n")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["title"] == "Example Article"
    assert data["author"] == "Jane Doe"
    assert data["published_date"] == "2025-01-01T12:00:00+00:00"
    assert data["domain"] == "example.com"
    assert data["reading_time"]


def test_rule_engine_removes_elements():
    html = "<html><body><div class='ad'>Ad</div><article><p>Keep</p></article></body></html>"
    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="remove-ad",
                phase="post",
                priority=0,
                trigger={"dom": {"any": [".ad"]}},
                remove=[".ad"],
                selector_overrides={},
                metadata={},
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    assert len(matched) == 1
    cleaned = engine.apply_rules(html, matched)
    assert "Ad" not in cleaned
    assert "Keep" in cleaned


def test_rule_engine_trigger_mode_any_text_contains():
    html = "<html><body><article><p>Hello world</p></article></body></html>"
    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="text-trigger",
                phase="post",
                priority=0,
                trigger={"mode": "any", "dom": {"any_text_contains": ["world"]}},
                remove=[".never"],
                selector_overrides={},
                metadata={},
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    assert len(matched) == 1


def test_metadata_overrides_apply(monkeypatch):
    html = """
    <html>
      <head>
        <title>Original</title>
      </head>
      <body>
        <article>
          <h1>Override Title</h1>
          <time datetime="2024-12-31T10:00:00Z">Dec 31</time>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article"

    rule = web_save_parser.Rule(
        id="meta-override",
        phase="post",
        priority=0,
        trigger={"dom": {"any": ["h1"]}},
        remove=[],
        selector_overrides={},
        metadata={
            "title": {"selector": "h1"},
            "published": {"selector": "time", "attr": "datetime"},
        },
    )

    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert parsed.title == "Override Title"
    assert parsed.published_at == datetime(2024, 12, 31, 10, 0, tzinfo=timezone.utc)
