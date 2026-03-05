"""Tests for the web-save local parser."""

from datetime import UTC, datetime

from api.services import (
    web_save_includes,
    web_save_parser,
    web_save_parser_twitter,
    web_save_parser_wsj,
)
from api.services.web_save_parser_apple_news import (
    extract_apple_news_publisher_url,
    resolve_apple_news_source_url,
)
from api.services.web_save_parser_twitter import TwitterStatusSnapshot
from api.services.web_save_tagger import calculate_reading_time
from bs4 import BeautifulSoup
from lxml import html as lxml_html
import pytest


def test_parse_url_local_builds_frontmatter(monkeypatch):
    html = """
    <html>
      <head>
        <title>Svelte Example Article</title>
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
        return html, "https://example.com/article?utm=ignored", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    parsed = web_save_parser.parse_url_local("example.com/article")

    assert parsed.title == "Svelte Example Article"
    assert parsed.source == "https://example.com/article"
    assert parsed.published_at == datetime(2025, 1, 1, 12, 0, tzinfo=UTC)
    assert parsed.content.startswith("---\n")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["title"] == "Svelte Example Article"
    assert data["author"] == "Jane Doe"
    assert data["published_date"] == "2025-01-01T12:00:00+00:00"
    assert data["domain"] == "example.com"
    assert data["reading_time"]
    assert "svelte" in data["tags"]


def test_parse_url_local_apple_news_fetches_publisher_article(monkeypatch):
    apple_html = """
    <html>
      <head>
        <title>Opening story</title>
        <script>
          redirectToUrlAfterTimeout("https://www.wsj.com/tech/ai/anthropic", 0);
        </script>
      </head>
      <body>
        <div class="inner-content">
          <h1>Opening story...</h1>
          <p><a href="https://www.wsj.com/tech/ai/anthropic">Tap here</a></p>
        </div>
      </body>
    </html>
    """
    publisher_html = """
    <html>
      <head><title>Publisher Story</title></head>
      <body>
        <article>
          <h1>Publisher Story</h1>
          <p>This text comes from the publisher article body.</p>
        </article>
      </body>
    </html>
    """
    fetch_calls: list[str] = []

    def fake_fetch(url: str, *, timeout: int = 30):
        fetch_calls.append(url)
        if "apple.news" in url:
            return apple_html, "https://apple.news/ASNJScnjXQj-AP4JENCN9NQ", False
        if "wsj.com" in url:
            return publisher_html, "https://www.wsj.com/tech/ai/anthropic", False
        raise AssertionError(f"Unexpected URL: {url}")

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    parsed = web_save_parser.parse_url_local(
        "https://apple.news/ASNJScnjXQj-AP4JENCN9NQ"
    )
    assert fetch_calls == [
        "https://apple.news/ASNJScnjXQj-AP4JENCN9NQ",
        "https://www.wsj.com/tech/ai/anthropic",
    ]
    assert parsed.source == "https://www.wsj.com/tech/ai/anthropic"
    assert "publisher article body" in parsed.content.lower()


def test_parse_url_local_wsj_preview_uses_jina_content_when_longer(monkeypatch):
    wsj_preview_html = """
    <html>
      <head><title>WSJ Story</title></head>
      <body>
        <article>
          <p>A short opening paragraph.</p>
          <p>Another short paragraph before the paywall marker.</p>
          <p>Copyright ©2026 Dow Jones & Company, Inc. All Rights Reserved. 87990cbe856818d5eddac44c7b1cdeb8</p>
        </article>
        <div>Continue reading your article with</div>
        <div>a WSJ subscription</div>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return wsj_preview_html, "https://www.wsj.com/tech/ai/story-id", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )
    monkeypatch.setattr(web_save_parser_wsj.settings, "jina_api_key", "test-jina-key")
    monkeypatch.setattr(
        web_save_parser_wsj.JinaService,
        "fetch_markdown",
        lambda _url: "ignored",
    )
    monkeypatch.setattr(
        web_save_parser_wsj.JinaService,
        "parse_metadata",
        lambda _markdown: (
            {
                "title": "WSJ Story (Full)",
                "url_source": "https://www.wsj.com/tech/ai/story-id",
                "published_time": None,
            },
            ("Full article paragraph. " * 200).strip(),
        ),
    )
    monkeypatch.setattr(
        web_save_parser_wsj.JinaService,
        "clean_markdown_for_source",
        lambda markdown, _source: markdown,
    )

    parsed = web_save_parser.parse_url_local("https://www.wsj.com/tech/ai/story-id")

    assert parsed.source == "https://www.wsj.com/tech/ai/story-id"
    assert "full article paragraph" in parsed.content.lower()


def test_parse_url_local_wsj_preview_raises_when_jina_fetch_fails(monkeypatch):
    wsj_preview_html = """
    <html>
      <head><title>WSJ Story</title></head>
      <body>
        <article>
          <p>A short opening paragraph.</p>
          <p>Copyright ©2026 Dow Jones & Company, Inc. All Rights Reserved. 87990cbe856818d5eddac44c7b1cdeb8</p>
        </article>
        <div>Continue reading your article with</div>
        <div>a WSJ subscription</div>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return wsj_preview_html, "https://www.wsj.com/tech/ai/story-id", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )
    monkeypatch.setattr(web_save_parser_wsj.settings, "jina_api_key", "test-jina-key")
    monkeypatch.setattr(
        web_save_parser_wsj.JinaService,
        "fetch_markdown",
        lambda _url: (_ for _ in ()).throw(RuntimeError("402 Payment Required")),
    )

    with pytest.raises(web_save_parser_wsj.WSJPreviewEnrichmentError) as exc_info:
        web_save_parser.parse_url_local("https://www.wsj.com/tech/ai/story-id")

    assert "WSJ preview detected but Jina fallback failed" in str(exc_info.value)


def test_parse_url_local_wsj_noisy_preview_marks_truncated(monkeypatch):
    wsj_preview_html = """
    <html>
      <head><title>WSJ Story</title></head>
      <body>
        <article>
          <h1>Meet the One Woman Anthropic Trusts to Teach AI Morals</h1>
          <p>Amanda Askell knew from the age of 14 that she wanted to teach philosophy.</p>
          <p>As the resident philosopher of the tech company Anthropic, Askell spends her days learning Claude's reasoning patterns.</p>
          <p>She compares her work to the efforts of a parent raising a child.</p>
          <p>Copyright ©2026 Dow Jones & Company, Inc. All Rights Reserved. 87990cbe856818d5eddac44c7b1cdeb8</p>
        </article>
        <div>Continue reading your article with</div>
        <div>a WSJ subscription</div>
        <ul>
          <li><a href="https://www.wsj.com/">The Wall Street Journal</a></li>
          <li><a href="https://subscribe.wsj.com/membership">Subscription Options</a></li>
          <li><a href="https://corporate.wsj.com/">Corporate Subscriptions</a></li>
        </ul>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return wsj_preview_html, "https://www.wsj.com/tech/ai/story-id", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )
    monkeypatch.setattr(web_save_parser_wsj.settings, "jina_api_key", "test-jina-key")
    monkeypatch.setattr(
        web_save_parser_wsj.JinaService,
        "fetch_markdown",
        lambda _url: "ignored",
    )
    monkeypatch.setattr(
        web_save_parser_wsj.JinaService,
        "parse_metadata",
        lambda _markdown: (
            {
                "title": "WSJ Story",
                "url_source": "https://www.wsj.com/tech/ai/story-id",
                "published_time": None,
            },
            "Short fallback snippet.",
        ),
    )

    parsed = web_save_parser.parse_url_local("https://www.wsj.com/tech/ai/story-id")

    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert data["paywalled"] is True
    assert data["truncated"] is True
    assert "Warning: This article appears truncated." in parsed.content
    assert "Corporate Subscriptions" not in parsed.content


def test_parse_url_local_uses_x_status_snapshot(monkeypatch):
    html = """
    <html>
      <head><title>X</title></head>
      <body><div id="react-root">app shell</div></body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://x.com/sean/status/1234567890", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )
    monkeypatch.setattr(
        web_save_parser,
        "fetch_twitter_status_snapshot",
        lambda _url: TwitterStatusSnapshot(
            title="Hello from X",
            markdown=(
                "**Sean** [@sean](https://x.com/sean) · March 5, 2026\n\n"
                "Hello from X.\n\n"
                "[Original post on X](https://x.com/sean/status/1234567890)"
            ),
            source_url="https://x.com/sean/status/1234567890",
            author="Sean",
        ),
    )

    parsed = web_save_parser.parse_url_local("https://x.com/sean/status/1234567890")

    assert parsed.title == "Hello from X"
    assert parsed.source == "https://x.com/sean/status/1234567890"
    assert "Hello from X." in parsed.content
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert data["title"] == "Hello from X"
    assert data["author"] == "Sean"
    assert data["domain"] == "x.com"


def test_parse_url_local_falls_back_when_x_status_snapshot_missing(monkeypatch):
    html = """
    <html>
      <head><title>Fallback Post</title></head>
      <body>
        <article>
          <p>This falls back to generic parsing when the snapshot is unavailable.</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://x.com/sean/status/1234567890", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )
    monkeypatch.setattr(
        web_save_parser, "fetch_twitter_status_snapshot", lambda _url: None
    )

    parsed = web_save_parser.parse_url_local("https://x.com/sean/status/1234567890")

    assert parsed.title == "Fallback Post"
    assert "falls back to generic parsing" in parsed.content.lower()


def test_fetch_twitter_status_snapshot_parses_oembed_markup(monkeypatch):
    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "author_name": "Sean",
                "author_url": "https://twitter.com/sean",
                "html": """
                <blockquote class="twitter-tweet">
                  <p lang="en" dir="ltr">
                    Hello <a href="https://example.com">world</a>
                  </p>
                  &mdash; Sean (@sean)
                  <a href="https://twitter.com/sean/status/1234567890?ref_src=twsrc%5Etfw">
                    March 5, 2026
                  </a>
                </blockquote>
                """,
            }

    monkeypatch.setattr(
        web_save_parser_twitter.requests,
        "get",
        lambda *args, **kwargs: FakeResponse(),
    )

    snapshot = web_save_parser_twitter.fetch_twitter_status_snapshot(
        "https://twitter.com/sean/status/1234567890"
    )

    assert snapshot is not None
    assert snapshot.title == "Hello world"
    assert snapshot.source_url == "https://x.com/sean/status/1234567890"
    assert (
        "**Sean** [@sean](https://x.com/sean) · March 5, 2026"
        in snapshot.markdown
    )
    assert "[Original post on X](https://x.com/sean/status/1234567890)" in snapshot.markdown


def test_fetch_twitter_status_snapshot_formats_command_lines(monkeypatch):
    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "author_name": "Guillermo Rauch",
                "author_url": "https://twitter.com/rauchg",
                "html": """
                <blockquote class="twitter-tweet">
                  <p lang="en" dir="ltr">
                    Google has shipped a CLI for Google Workspace Huge!<br><br>
                    $ npm i -g @&#8288;googleworkspace/cli<br>
                    $ npx skills add github:googleworkspace/cli<br><br>
                    2026 is the year of Skills &amp; CLIs…
                  </p>
                  <a href="https://twitter.com/rauchg/status/2029356560494018956">
                    March 5, 2026
                  </a>
                </blockquote>
                """,
            }

    monkeypatch.setattr(
        web_save_parser_twitter.requests,
        "get",
        lambda *args, **kwargs: FakeResponse(),
    )

    snapshot = web_save_parser_twitter.fetch_twitter_status_snapshot(
        "https://x.com/rauchg/status/2029356560494018956"
    )

    assert snapshot is not None
    assert "[@rauchg](https://x.com/rauchg)" in snapshot.markdown
    assert "@googleworkspace/cli" in snapshot.markdown
    assert "@⁠googleworkspace/cli" not in snapshot.markdown
    assert "```bash" in snapshot.markdown
    assert "$ npm i -g @googleworkspace/cli" in snapshot.markdown
    assert "$ npx skills add github:googleworkspace/cli" in snapshot.markdown


def test_extract_metadata_finds_favicon():
    html = """
    <html>
      <head>
        <link rel="icon" href="/favicon.png"/>
      </head>
      <body></body>
    </html>
    """
    metadata = web_save_parser.extract_metadata(html, "https://example.com/article")
    assert metadata["favicon"] == "/favicon.png"


def test_extract_metadata_ignores_undefined_canonical():
    html = """
    <html>
      <head>
        <link rel="canonical" href="undefined"/>
      </head>
      <body></body>
    </html>
    """
    metadata = web_save_parser.extract_metadata(html, "https://example.com/article")
    assert metadata["canonical"] == "https://example.com/article"


def test_extract_apple_news_publisher_url_prefers_redirect_script():
    html = """
    <html>
      <head>
        <script>
          function foo() {
            redirectToUrlAfterTimeout("https://www.wsj.com/tech/ai/story-id", 0);
          }
        </script>
      </head>
      <body>
        <div class="inner-content">
          <p><a href="https://www.example.com/fallback">Tap here</a></p>
        </div>
      </body>
    </html>
    """
    extracted = extract_apple_news_publisher_url(html)
    assert extracted == "https://www.wsj.com/tech/ai/story-id"


def test_resolve_apple_news_source_url_resolves_publisher(monkeypatch):
    html = """
    <html>
      <head>
        <script>
          redirectToUrlAfterTimeout("https://www.wsj.com/tech/ai/story-id", 0);
        </script>
      </head>
    </html>
    """

    class FakeResponse:
        status_code = 200
        encoding = "utf-8"
        content = html.encode("utf-8")

        def raise_for_status(self):
            return None

    def fake_get(url: str, headers=None, timeout: int = 12):
        return FakeResponse()

    monkeypatch.setattr(
        "api.services.web_save_parser_apple_news.requests.get",
        fake_get,
    )

    resolved = resolve_apple_news_source_url(
        "https://apple.news/ASNJScnjXQj-AP4JENCN9NQ"
    )
    assert resolved == "https://www.wsj.com/tech/ai/story-id"


def test_resolve_apple_news_source_url_passthrough_non_apple(monkeypatch):
    def fake_get(url: str, headers=None, timeout: int = 12):
        raise AssertionError("network should not be called for non-apple urls")

    monkeypatch.setattr(
        "api.services.web_save_parser_apple_news.requests.get",
        fake_get,
    )

    resolved = resolve_apple_news_source_url("https://example.com/post")
    assert resolved == "https://example.com/post"


def test_resolve_favicon_url_falls_back(monkeypatch):
    monkeypatch.setattr(web_save_parser, "_favicon_exists", lambda url, timeout=8: True)
    resolved = web_save_parser.resolve_favicon_url(None, "https://example.com/article")
    assert resolved == "https://example.com/favicon.ico"


def test_extract_favicon_url_fetches_html(monkeypatch):
    html = """
    <html>
      <head>
        <link rel="icon" href="/favicon.png"/>
      </head>
      <body></body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    resolved = web_save_parser.extract_favicon_url("https://example.com/article")
    assert resolved == "https://example.com/favicon.png"


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
                include=[],
                selector_overrides={},
                metadata={},
                actions=[],
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
                include=[],
                selector_overrides={},
                metadata={},
                actions=[],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    assert len(matched) == 1


def test_rule_engine_handles_comment_root():
    html = "<!--comment--><article><p>Hello world</p></article>"
    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="comment-safe",
                phase="post",
                priority=0,
                trigger={"mode": "any", "dom": {"any_text_contains": ["world"]}},
                remove=[],
                include=[],
                selector_overrides={},
                metadata={},
                actions=[],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    assert len(matched) == 1


def test_metadata_overrides_handles_comment_root():
    html = "<!--comment--><article><h1>Title</h1></article>"
    rules = [
        web_save_parser.Rule(
            id="meta-comment",
            phase="post",
            priority=0,
            trigger={"mode": "any", "dom": {"any": ["h1"]}},
            remove=[],
            include=[],
            selector_overrides={},
            metadata={"title": {"selector": "h1"}},
            actions=[],
        )
    ]
    overrides = web_save_parser.extract_metadata_overrides(html, rules)
    assert overrides["title"] == "Title"


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
        return html, "https://example.com/article", False

    rule = web_save_parser.Rule(
        id="meta-override",
        phase="post",
        priority=0,
        trigger={"dom": {"any": ["h1"]}},
        remove=[],
        include=[],
        selector_overrides={},
        metadata={
            "title": {"selector": "h1"},
            "published": {"selector": "time", "attr": "datetime"},
        },
        actions=[],
    )

    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert parsed.title == "Override Title"
    assert parsed.published_at == datetime(2024, 12, 31, 10, 0, tzinfo=UTC)


def test_rule_engine_actions_retag_and_unwrap():
    html = "<html><body><div class='wrap'><span class='title'>Hello</span></div></body></html>"
    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="actions",
                phase="post",
                priority=0,
                trigger={"dom": {"any": [".title"]}},
                remove=[],
                include=[],
                selector_overrides={},
                metadata={},
                actions=[
                    {"op": "retag", "selector": ".title", "tag": "h1"},
                    {"op": "unwrap", "selector": ".wrap"},
                ],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    cleaned = engine.apply_rules(html, matched)
    assert "<h1" in cleaned
    assert "wrap" not in cleaned


def test_rule_engine_actions_move_and_set_attr():
    html = (
        "<html><body><div class='target'></div><p class='move'>Move</p></body></html>"
    )
    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="move",
                phase="post",
                priority=0,
                trigger={"dom": {"any": [".move"]}},
                remove=[],
                include=[],
                selector_overrides={},
                metadata={},
                actions=[
                    {"op": "move", "selector": ".move", "target": ".target"},
                    {
                        "op": "set_attr",
                        "selector": ".target",
                        "attr": "data-test",
                        "value": "ok",
                    },
                ],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    cleaned = engine.apply_rules(html, matched)
    assert 'data-test="ok"' in cleaned
    assert cleaned.find("Move") < cleaned.find("</div>")


def test_rule_engine_actions_group_siblings():
    html = "<html><body><p class='cap'>A</p><p class='cap'>B</p><p>C</p></body></html>"
    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="group",
                phase="post",
                priority=0,
                trigger={"dom": {"any": [".cap"]}},
                remove=[],
                include=[],
                selector_overrides={},
                metadata={},
                actions=[
                    {
                        "op": "group_siblings",
                        "selector": ".cap",
                        "wrapper_tag": "div",
                        "class": "caps",
                    },
                ],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    cleaned = engine.apply_rules(html, matched)
    assert 'class="caps"' in cleaned


def test_rule_engine_actions_remove_children():
    html = (
        "<html><body><div class='box'><p>Remove me</p></div><p>Keep</p></body></html>"
    )
    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="remove-children",
                phase="post",
                priority=0,
                trigger={"dom": {"any": [".box"]}},
                remove=[],
                include=[],
                selector_overrides={},
                metadata={},
                actions=[{"op": "remove_children", "selector": ".box"}],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    cleaned = engine.apply_rules(html, matched)
    assert "Remove me" not in cleaned
    assert "Keep" in cleaned


def test_parse_url_local_discard_rule(monkeypatch):
    html = "<html><head><title>Discard Me</title></head><body><article>Skip</article></body></html>"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/discard", False

    rule = web_save_parser.Rule(
        id="discard-it",
        phase="pre",
        priority=0,
        trigger={"dom": {"any": ["article"]}},
        discard=True,
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    parsed = web_save_parser.parse_url_local("example.com/discard")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert data["discarded"] is True
    assert data["rule_id"] == "discard-it"


def test_parse_url_local_raises_fallback_error_for_discard_rule(monkeypatch):
    html = "<html><head><title>Fallback</title></head><body><article>Skip</article></body></html>"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/fallback", False

    rule = web_save_parser.Rule(
        id="discard-fallback",
        phase="pre",
        priority=0,
        trigger={"dom": {"any": ["article"]}},
        discard=True,
        fallback="jina",
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    with pytest.raises(web_save_parser.LocalParseFallbackError) as exc_info:
        web_save_parser.parse_url_local("example.com/fallback")

    assert exc_info.value.fallback == "jina"
    assert exc_info.value.rule_id == "discard-fallback"


def test_archive_family_captcha_rules_match_pre_phase():
    html = """
    <html>
      <body>
        <h1>One more step</h1>
        <div id="g-recaptcha"></div>
      </body>
    </html>
    """
    engine = web_save_parser.get_rule_engine()
    cases = [
        ("https://archive.is/QSErS", "archiveis-captcha-discard"),
        ("https://archive.ph/QSErS", "archiveph-captcha-discard"),
        ("https://archive.today/QSErS", "archivetoday-captcha-discard"),
        ("https://archive.md/QSErS", "archivemd-captcha-discard"),
    ]

    for url, rule_id in cases:
        matched = engine.match_rules(url, html, phase="pre")
        matched_ids = {rule.id for rule in matched}
        assert rule_id in matched_ids


def test_parse_url_local_archiveis_captcha_requests_fallback(monkeypatch):
    html = """
    <html>
      <head><title>archive.is</title></head>
      <body>
        <h1>One more step</h1>
        <div id="g-recaptcha"></div>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://archive.is/QSErS", True

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser,
        "_favicon_exists",
        lambda url, timeout=8: False,
    )

    with pytest.raises(web_save_parser.LocalParseFallbackError) as exc_info:
        web_save_parser.parse_url_local("https://archive.is/QSErS")

    assert exc_info.value.fallback == "jina"
    assert exc_info.value.rule_id == "archiveis-captcha-discard"


def test_campaignlive_paywall_rule_matches_pre_phase():
    html = """
    <html>
      <body>
        <h1>Eight principles for ad practitioners to use AI responsibly</h1>
        <h2>Sign in to continue</h2>
      </body>
    </html>
    """
    engine = web_save_parser.get_rule_engine()
    matched = engine.match_rules(
        "https://www.campaignlive.co.uk/article/example/1947988",
        html,
        phase="pre",
    )
    matched_ids = {rule.id for rule in matched}
    assert "campaignlive-paywall-discard" in matched_ids


def test_campaignlive_paywall_rule_matches_post_phase():
    html = """
    <html>
      <body>
        <h1>Eight principles for ad practitioners to use AI responsibly</h1>
        <h2>Sign in to continue</h2>
      </body>
    </html>
    """
    engine = web_save_parser.get_rule_engine()
    matched = engine.match_rules(
        "https://www.campaignlive.co.uk/article/example/1947988",
        html,
        phase="post",
    )
    matched_ids = {rule.id for rule in matched}
    assert "campaignlive-paywall-discard" in matched_ids


def test_parse_url_local_campaignlive_paywall_discards_content(monkeypatch):
    html = """
    <html>
      <head><title>Eight principles</title></head>
      <body>
        <h1>Eight principles for ad practitioners to use AI responsibly</h1>
        <h2>Sign in to continue</h2>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return (
            html,
            "https://www.campaignlive.co.uk/article/eight-principles/1947988",
            False,
        )

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local(
        "https://www.campaignlive.co.uk/article/eight-principles/1947988"
    )
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert data["discarded"] is True
    assert data["rule_id"] == "campaignlive-paywall-discard"
    assert "[Content discarded by parsing rule]" in parsed.content


def test_tryprofound_article_override_rule_matches_pre_phase():
    html = """
    <html>
      <body>
        <main>
          <div class="content-grid">
            <article><h1>How ChatGPT cites social media</h1></article>
            <article><h2>Teaser</h2></article>
          </div>
        </main>
      </body>
    </html>
    """
    engine = web_save_parser.get_rule_engine()
    matched = engine.match_rules(
        "https://www.tryprofound.com/blog/chatgpt-reddit-youtube-citations",
        html,
        phase="pre",
    )
    matched_ids = {rule.id for rule in matched}
    assert "tryprofound-article-override" in matched_ids


def test_parse_url_local_tryprofound_scopes_to_primary_article(monkeypatch):
    html = """
    <html>
      <head>
        <title>How ChatGPT cites social media</title>
        <meta property="og:image" content="https://cdn.sanity.io/images/example.png"/>
      </head>
      <body>
        <main>
          <div class="content-grid">
            <article>
              <h1>How ChatGPT cites social media</h1>
              <p>When AI models answer questions, they increasingly turn to social platforms as sources of truth.</p>
              <p>Reddit and YouTube now dominate citations in several categories.</p>
            </article>
            <article>
              <h2>Profound now integrates with Slack</h2>
              <p>Adding a Slack node to a Profound Agent helps teams stay aligned.</p>
            </article>
          </div>
        </main>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return (
            html,
            "https://www.tryprofound.com/blog/chatgpt-reddit-youtube-citations",
            False,
        )

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local(
        "https://www.tryprofound.com/blog/chatgpt-reddit-youtube-citations"
    )
    assert "When AI models answer questions" in parsed.content
    assert "Reddit and YouTube now dominate citations" in parsed.content
    assert "Profound now integrates with Slack" not in parsed.content


def test_airbnb_listing_rule_matches_pre_phase():
    html = """
    <html>
      <head>
        <meta name="application-name" content="Airbnb"/>
      </head>
      <body>
        <script>
          window.__bootstrap = {"pdpPresentation": {"node": {"__typename": "DemandStayListing"}}};
        </script>
      </body>
    </html>
    """
    engine = web_save_parser.get_rule_engine()
    matched = engine.match_rules(
        "https://www.airbnb.co.uk/rooms/29759249?viralityEntryPoint=1&s=76",
        html,
        phase="pre",
    )
    matched_ids = {rule.id for rule in matched}
    assert "airbnb-listing-fallback-co-uk" in matched_ids


def test_parse_url_local_airbnb_listing_requests_fallback(monkeypatch):
    html = """
    <html>
      <head><title>Airbnb</title></head>
      <body>
        <script>
          window.__bootstrap = {"pdpPresentation": {"node": {"__typename": "DemandStayListing"}}};
        </script>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return (
            html,
            "https://www.airbnb.co.uk/rooms/29759249?viralityEntryPoint=1&s=76",
            False,
        )

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser,
        "_favicon_exists",
        lambda url, timeout=8: False,
    )

    with pytest.raises(web_save_parser.LocalParseFallbackError) as exc_info:
        web_save_parser.parse_url_local(
            "https://www.airbnb.co.uk/rooms/29759249?viralityEntryPoint=1&s=76"
        )

    assert exc_info.value.fallback == "jina"
    assert exc_info.value.rule_id == "airbnb-listing-fallback-co-uk"


def test_parse_url_local_includes_reinserted_nodes(monkeypatch):
    html = """
    <html>
      <head><title>Include Me</title></head>
      <body>
        <div class="include-me"><p>Special include</p></div>
        <article><p>Primary content</p></article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/include", False

    rule = web_save_parser.Rule(
        id="include-rule",
        phase="pre",
        priority=0,
        trigger={"dom": {"any": [".include-me"]}},
        include=[".include-me"],
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    parsed = web_save_parser.parse_url_local("example.com/include")
    assert "Special include" in parsed.content


def test_parse_url_local_blog_google_reinserts_missing_modules(monkeypatch):
    html = """
    <html>
      <head><title>Game Arena</title></head>
      <body>
        <div class="article-summary__content">
          <p>Read AI-generated summary</p>
        </div>
        <div class="module--text module--text__article">
          <div class="rich-text">
            <h2>Chess: reasoning over calculation</h2>
            <p>Chess section details.</p>
          </div>
        </div>
        <div class="module--text module--text__article">
          <div class="rich-text">
            <h2>Werewolf: navigating social deduction</h2>
            <p>Werewolf section details.</p>
          </div>
        </div>
        <uni-image-full-width>
          <div slot="image-slot">
            <img alt="Werewolf board" src="https://images.example.com/werewolf.png"/>
          </div>
        </uni-image-full-width>
        <article>
          <div class="module--text module--text__article">
            <div class="rich-text">
              <h2>Poker: the challenge of calculated risk</h2>
              <p>Poker section details.</p>
            </div>
          </div>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://blog.google/example", False

    rule = web_save_parser.Rule(
        id="blog-google-include-article-modules",
        phase="pre",
        priority=0,
        trigger={"host": {"ends_with": "blog.google"}},
        include=[
            ".module--text__article",
            "uni-pull-quote",
            "uni-image-full-width",
        ],
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    parsed = web_save_parser.parse_url_local("blog.google/example")

    assert "Chess: reasoning over calculation" in parsed.content
    assert "Werewolf: navigating social deduction" in parsed.content
    assert "Poker: the challenge of calculated risk" in parsed.content
    assert "Werewolf board" in parsed.content
    assert parsed.content.find(
        "Chess: reasoning over calculation"
    ) < parsed.content.find("Poker: the challenge of calculated risk")


def test_parse_url_local_blog_google_preserves_ordered_modules(monkeypatch):
    html = """
    <html>
      <head><title>Game Arena</title></head>
      <body>
        <div class="uni-content uni-blog-article-container article-container__content" data-component="uni-article-body">
          <div class="article-summary__content">
            <p>Read AI-generated summary</p>
          </div>
          <div class="module--text module--text__article">
            <div class="rich-text">
              <p>Chess is a game of perfect information. The real world is not.</p>
              <p>Last year, Google DeepMind partnered with Kaggle to launch Game Arena.</p>
            </div>
          </div>
          <div class="module--text module--text__article">
            <div class="rich-text">
              <h2>Chess: reasoning over calculation</h2>
              <p>Chess section details.</p>
            </div>
          </div>
          <div class="module--text module--text__article">
            <div class="rich-text">
              <h2>Werewolf: navigating social deduction</h2>
              <p>Werewolf section details.</p>
            </div>
          </div>
          <div class="module--text module--text__article">
            <div class="rich-text">
              <h2>Poker: the challenge of calculated risk</h2>
              <p>Poker section details.</p>
              <h2>Watch the action</h2>
              <p>Watch section details.</p>
              <h2>Explore the arena</h2>
              <p>Explore section details.</p>
            </div>
          </div>
        </div>
        <article>
          <div class="module--text module--text__article">
            <div class="rich-text">
              <h2>Poker: the challenge of calculated risk</h2>
              <p>Poker section details.</p>
              <h2>Watch the action</h2>
              <p>Watch section details.</p>
            </div>
          </div>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://blog.google/example", False

    rule = web_save_parser.Rule(
        id="blog-google-include-article-modules",
        phase="pre",
        priority=0,
        trigger={"host": {"ends_with": "blog.google"}},
        include=[
            ".module--text__article",
            "uni-pull-quote",
            "uni-image-full-width",
        ],
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    parsed = web_save_parser.parse_url_local("blog.google/example")

    assert "Read AI-generated summary" not in parsed.content
    assert parsed.content.find(
        "Chess is a game of perfect information. The real world is not."
    ) < parsed.content.find("## Chess: reasoning over calculation")
    assert parsed.content.find(
        "## Chess: reasoning over calculation"
    ) < parsed.content.find("## Werewolf: navigating social deduction")
    assert parsed.content.find(
        "## Werewolf: navigating social deduction"
    ) < parsed.content.find("## Poker: the challenge of calculated risk")
    assert parsed.content.find(
        "## Poker: the challenge of calculated risk"
    ) < parsed.content.find("## Watch the action")
    assert parsed.content.find("## Watch the action") < parsed.content.find(
        "## Explore the arena"
    )
    assert parsed.content.count("## Watch the action") == 1
    assert parsed.content.count("## Explore the arena") == 1


def test_apply_include_reinsertion_handles_comment_root():
    extracted_html = "<!--comment--><article><p>Primary content</p></article>"
    original_html = """
    <html>
      <body>
        <div class="include-me"><p>Special include</p></div>
        <article><p>Primary content</p></article>
      </body>
    </html>
    """
    original_dom = lxml_html.fromstring(original_html)
    updated = web_save_includes.apply_include_reinsertion(
        extracted_html,
        original_dom,
        include_selectors=[".include-me"],
        removal_rules=[],
    )
    assert "Special include" in updated


def test_apply_include_reinsertion_preserves_include_order():
    extracted_html = "<article><p>Anchor</p></article>"
    original_html = """
    <html>
      <body>
        <div class="gallery">First gallery</div>
        <p>Anchor</p>
        <div class="gallery">Second gallery</div>
      </body>
    </html>
    """
    original_dom = lxml_html.fromstring(original_html)
    updated = web_save_includes.apply_include_reinsertion(
        extracted_html,
        original_dom,
        include_selectors=[".gallery"],
        removal_rules=[],
    )
    first_index = updated.find("First gallery")
    second_index = updated.find("Second gallery")
    assert first_index != -1
    assert second_index != -1
    assert first_index < second_index


def test_apply_include_reinsertion_skips_comment_siblings_for_positioning():
    extracted_html = """
    <article>
      <div class="module--text module--text__article">
        <h2>Poker: the challenge of calculated risk</h2>
        <p>Poker section details.</p>
      </div>
    </article>
    """
    original_html = """
    <html>
      <body>
        <div class="module--text module--text__article">
          <h2>Chess: reasoning over calculation</h2>
          <p>Chess section details.</p>
        </div>
        <!-- Readability drops earlier modules on this page shape -->
        <div class="module--text module--text__article">
          <h2>Werewolf: navigating social deduction</h2>
          <p>Werewolf section details.</p>
        </div>
        <article>
          <div class="module--text module--text__article">
            <h2>Poker: the challenge of calculated risk</h2>
            <p>Poker section details.</p>
          </div>
        </article>
      </body>
    </html>
    """
    original_dom = lxml_html.fromstring(original_html)
    updated = web_save_includes.apply_include_reinsertion(
        extracted_html,
        original_dom,
        include_selectors=[".module--text__article"],
        removal_rules=[],
    )
    assert "Chess: reasoning over calculation" in updated
    assert "Werewolf: navigating social deduction" in updated
    assert "Poker: the challenge of calculated risk" in updated
    assert updated.find("Chess: reasoning over calculation") < updated.find(
        "Werewolf: navigating social deduction"
    )


def test_apply_include_reinsertion_skips_existing_long_module_content():
    extracted_html = """
    <article>
      <p>Chess is a game of perfect information. The real world is not.</p>
      <p>Chess relies on reasoning. Werewolf relies on social deduction. Poker introduces a new dimension: risk management.</p>
      <h2>Watch the action</h2>
      <p>Marking the launch of these new and updated benchmarks, we have partnered with experts for analysis.</p>
      <h2>Explore the arena</h2>
      <p>Check it out at <a href="http://kaggle.com/game-arena">kaggle.com/game-arena</a>.</p>
    </article>
    """
    original_html = """
    <html>
      <body>
        <div class="module--text module--text__article">
          <div class="rich-text">
            <h2>Chess: reasoning over calculation</h2>
            <p>Chess section details.</p>
          </div>
        </div>
        <div class="module--text module--text__article">
          <div class="rich-text">
            <p>Chess relies on reasoning. Werewolf relies on social deduction. Poker introduces a new dimension: risk management.</p>
            <h2>Watch the action</h2>
            <p>Marking the launch of these new and updated benchmarks, we have partnered with experts for analysis.</p>
            <h2>Explore the arena</h2>
            <p>Check it out at <a href="http://kaggle.com/game-arena">kaggle.com/game-arena</a>.</p>
          </div>
        </div>
      </body>
    </html>
    """
    original_dom = lxml_html.fromstring(original_html)
    updated = web_save_includes.apply_include_reinsertion(
        extracted_html,
        original_dom,
        include_selectors=[".module--text__article"],
        removal_rules=[],
    )
    assert "Chess: reasoning over calculation" in updated
    assert updated.count("Watch the action") == 1
    assert updated.count("Explore the arena") == 1
    assert (
        updated.count(
            "Chess relies on reasoning. Werewolf relies on social deduction. Poker introduces a new dimension: risk management."
        )
        == 1
    )


def test_apply_include_reinsertion_uses_ancestor_siblings_for_position():
    extracted_html = "<article><p>Before</p><p>Between</p><p>After</p></article>"
    original_html = """
    <html>
      <body>
        <div><p>Before</p></div>
        <div class="wrap"><section class="duet--article--gallery">G1</section></div>
        <p>Between</p>
        <div class="wrap"><section class="duet--article--gallery">G2</section></div>
        <p>After</p>
      </body>
    </html>
    """
    original_dom = lxml_html.fromstring(original_html)
    updated = web_save_includes.apply_include_reinsertion(
        extracted_html,
        original_dom,
        include_selectors=[".duet--article--gallery"],
        removal_rules=[],
    )
    before_index = updated.find("Before")
    between_index = updated.find("Between")
    g1_index = updated.find("G1")
    g2_index = updated.find("G2")
    assert before_index < g1_index < between_index
    assert between_index < g2_index


def test_apply_include_reinsertion_verge_gallery_uses_paragraph_index():
    extracted_html = "<article><p>Repeat</p><p>Repeat</p><p>After</p></article>"
    original_html = """
    <html>
      <body>
        <article>
          <p>Repeat</p>
          <p>Repeat</p>
          <section class="duet--article--gallery">G2</section>
          <p>After</p>
        </article>
      </body>
    </html>
    """
    original_dom = lxml_html.fromstring(original_html)
    updated = web_save_includes.apply_include_reinsertion(
        extracted_html,
        original_dom,
        include_selectors=[".duet--article--gallery"],
        removal_rules=[],
    )
    first_repeat = updated.find("<p>Repeat</p>")
    second_repeat = updated.find("<p>Repeat</p>", first_repeat + 1)
    g2_index = updated.find("G2")
    assert second_repeat < g2_index


def test_cleanup_verge_markdown_removes_gallery_chrome():
    markdown = "\n".join(
        [
            "**1/5**Image: Dominic Preston / The Verge",
            "[![](https://platform.theverge.com/wp-content/uploads/a.jpg)](https://platform.theverge.com/wp-content/uploads/a.jpg)",
            "PreviousNext",
            "**1/2**Image: Hyundai",
        ]
    )
    cleaned = web_save_parser.cleanup_verge_markdown(markdown)
    assert "Image: Dominic Preston" not in cleaned
    assert "PreviousNext" not in cleaned
    assert "Image: Hyundai" not in cleaned


def test_cleanup_verge_markdown_removes_follow_topics_block():
    markdown = "\n".join(
        [
            "**Follow topics and authors** from this story to see more like this.",
            "",
            "* Andrew J. Hawkins",
            "* Autonomous Cars",
            "* Cars",
            "",
            "Next paragraph.",
        ]
    )
    cleaned = web_save_parser.cleanup_verge_markdown(markdown)
    assert "Follow topics and authors" not in cleaned
    assert "Andrew J. Hawkins" not in cleaned
    assert "Autonomous Cars" not in cleaned
    assert "Next paragraph." in cleaned


def test_iter_youtube_elements_skips_verge_non_body_component():
    html = """
    <html>
      <body>
        <article>
          <div class="ad-slot" data-testid="advertisement">
            <iframe src="https://www.youtube.com/embed/abcd1234"></iframe>
          </div>
        </article>
      </body>
    </html>
    """
    dom = lxml_html.fromstring(html)
    results = web_save_parser._iter_youtube_elements(
        dom, "https://www.theverge.com/test"
    )
    assert results == []


def test_iter_youtube_elements_allows_verge_body_component():
    html = """
    <html>
      <body>
        <article>
          <div class="duet--article--article-body-component">
            <iframe src="https://www.youtube.com/embed/abcd1234"></iframe>
          </div>
        </article>
      </body>
    </html>
    """
    dom = lxml_html.fromstring(html)
    results = web_save_parser._iter_youtube_elements(
        dom, "https://www.theverge.com/test"
    )
    assert [item[0] for item in results] == ["abcd1234"]


def test_techcrunch_cleanup_removes_inline_cta():
    html = """
    <html>
      <body>
        <article>
          <p>Before</p>
          <div class="inline-cta__wrapper">
            <div class="inline-cta__flag">Techcrunch event</div>
          </div>
          <p>After</p>
        </article>
      </body>
    </html>
    """
    engine = web_save_parser.get_rule_engine()
    matched = engine.match_rules(
        "https://techcrunch.com/2025/08/28/example", html, phase="post"
    )
    assert any(rule.id == "techcrunch-cleanup" for rule in matched)
    cleaned = engine.apply_rules(html, matched)
    assert "Techcrunch event" not in cleaned


def test_cleanup_gizmodo_markdown_removes_io9_promo():
    markdown = "\n".join(
        [
            "> Want more io9 news? Check out when to expect the latest Marvel releases.",
            "> And everything you need to know about the future of Doctor Who.",
            "",
            "Next paragraph.",
        ]
    )
    cleaned = web_save_parser.cleanup_gizmodo_markdown(markdown)
    assert "want more io9 news" not in cleaned.lower()
    assert "Next paragraph." in cleaned


def test_9to5mac_cleanup_removes_youtube_cta_and_disclaimer():
    html = """
    <html>
      <body>
        <article>
          <div class="article__youtube-video">
            <iframe src="https://www.youtube.com/embed/71phz7W0Z1U"></iframe>
          </div>
          <h3 id="h-best-iphone-accessories">Best iPhone accessories</h3>
          <div class="ad-disclaimer-container">
            <p class="disclaimer-affiliate">FTC: We use income earning auto affiliate links.</p>
          </div>
          <p>Keep me</p>
        </article>
      </body>
    </html>
    """
    engine = web_save_parser.get_rule_engine()
    matched = engine.match_rules(
        "https://9to5mac.com/2026/01/01/example", html, phase="post"
    )
    assert any(rule.id == "9to5mac-cleanup" for rule in matched)
    cleaned = engine.apply_rules(html, matched)
    assert "article__youtube-video" not in cleaned
    assert "Best iPhone accessories" not in cleaned
    assert "FTC: We use income earning auto affiliate links." not in cleaned
    assert "Keep me" in cleaned


def test_iter_youtube_elements_skips_9to5mac_cta_video():
    html = """
    <html>
      <body>
        <article>
          <div class="article__youtube-video">
            <iframe src="https://www.youtube.com/embed/71phz7W0Z1U"></iframe>
          </div>
        </article>
      </body>
    </html>
    """
    dom = lxml_html.fromstring(html)
    results = web_save_parser._iter_youtube_elements(
        dom, "https://9to5mac.com/2026/01/01/example"
    )
    assert results == []


def test_cleanup_youtube_markdown_keeps_single_embed():
    markdown = "\n".join(
        [
            "![Thumb](https://i.ytimg.com/vi/FUq9qRwrDrI/maxresdefault.jpg)",
            "[About](https://www.youtube.com/about/)",
            "[YouTube](https://www.youtube.com/watch?v=FUq9qRwrDrI)",
            "[Privacy](https://www.youtube.com/t/privacy)",
        ]
    )
    cleaned = web_save_parser.cleanup_youtube_markdown(
        markdown, "https://www.youtube.com/watch?v=FUq9qRwrDrI"
    )
    assert cleaned.strip() == "[YouTube](https://www.youtube.com/watch?v=FUq9qRwrDrI)"


def test_cleanup_youtube_markdown_handles_shorts_source_url():
    markdown = (
        '<svg class="external-icon"></svg>[About](https://www.youtube.com/about/)'
        "[Privacy](https://www.youtube.com/t/privacy)"
    )
    cleaned = web_save_parser.cleanup_youtube_markdown(
        markdown, "https://www.youtube.com/shorts/Kg3VeW7yEyY"
    )
    assert cleaned.strip() == "[YouTube](https://www.youtube.com/watch?v=Kg3VeW7yEyY)"


def test_cleanup_openai_markdown_removes_credits_block():
    markdown = "\n".join(
        [
            "Intro paragraph.",
            "",
            "ResearchHarold Li, Dmytro Okhonko, Avi Verma",
            "",
            "ProductAndrew Kondrich, Andrew Sima",
            "",
            "Leadership",
            "",
            "Bill Peebles",
            "",
            "Built by OpenAI in San Francisco, California",
            "Published September 30, MMXXV",
        ]
    )
    cleaned = web_save_parser.cleanup_openai_markdown(markdown)
    assert "ResearchHarold Li" not in cleaned
    assert "ProductAndrew Kondrich" not in cleaned
    assert "Bill Peebles" not in cleaned
    assert "Built by OpenAI in San Francisco, California" in cleaned


def test_extract_openai_body_html_prefers_article_and_removes_nav():
    html = """
    <html>
      <body>
        <main>
          <nav>Nav</nav>
          <article><p>Keep this.</p></article>
        </main>
      </body>
    </html>
    """
    extracted = web_save_parser.extract_openai_body_html(html)
    assert extracted is not None
    assert "Keep this." in extracted
    assert "Nav" not in extracted


def test_extract_verge_body_html_combines_body_components():
    html = """
    <html>
      <body>
        <div class="duet--article--article-body-component">
          <p>First paragraph of article content.</p>
          <p>Second paragraph here.</p>
        </div>
        <div class="sidebar">Sidebar content</div>
        <div class="duet--article--article-body-component">
          <p>Third paragraph continues.</p>
          <div class="NewsletterSignup">Sign up for newsletter</div>
        </div>
        <aside>Related links</aside>
      </body>
    </html>
    """
    extracted = web_save_parser.extract_verge_body_html(html)
    assert extracted is not None
    assert "First paragraph" in extracted
    assert "Second paragraph" in extracted
    assert "Third paragraph" in extracted
    # Noise elements should be removed
    assert "Sign up for newsletter" not in extracted


def test_extract_verge_body_html_returns_none_when_no_body_components():
    html = "<html><body><p>No article structure</p></body></html>"
    extracted = web_save_parser.extract_verge_body_html(html)
    assert extracted is None


def test_cleanup_openai_markdown_removes_footer_and_chrome():
    markdown = "\n".join(
        [
            "Intro paragraph.",
            "",
            "[Research](https://openai.com/news/research/)[Release](https://openai.com/research/index/release/)",
            "",
            "[Download the Sora app(opens in a new window)](https://apps.apple.com/app/id123)",
            "Loading…",
            "Share",
            "",
            "Built by OpenAI in San Francisco, California",
            "Published September 30, MMXXV",
            "",
            "## Author",
            "[The Sora team](https://openai.com/news/?author=the-sora-team#results)",
            "",
            "## Keep reading",
            "[View all](https://openai.com/news/research/)",
        ]
    )
    cleaned = web_save_parser.cleanup_openai_markdown(markdown)
    assert "Loading…" not in cleaned
    assert "Share" not in cleaned
    assert "openai.com/news/research" not in cleaned
    assert "opens in a new window" not in cleaned
    assert "Intro paragraph." in cleaned
    assert "Built by OpenAI in San Francisco, California" in cleaned


def test_cleanup_openai_markdown_removes_category_links_row():
    markdown = "\n".join(
        [
            "[Product](https://openai.com/news/product-releases/)[Release](https://openai.com/research/index/release/)",
            "Keep this paragraph.",
        ]
    )
    cleaned = web_save_parser.cleanup_openai_markdown(markdown)
    assert "Product" not in cleaned
    assert "Release" not in cleaned
    assert "Keep this paragraph." in cleaned


def test_cleanup_github_markdown_removes_octicon_heading_anchors():
    markdown = "\n".join(
        [
            "# Repo",
            "",
            '[<svg aria-hidden="true" class="octicon octicon-link"><path d="M0 0"></path></svg>](#models-selection--auth)',
            "",
            "## Models (selection + auth)",
            "",
            '[<svg aria-hidden="true" class="octicon octicon-mark-github"><path d="M0 0"></path></svg>](https://github.com)',
        ]
    )

    cleaned = web_save_parser.cleanup_github_markdown(markdown)

    assert "octicon-link" not in cleaned
    assert "(#models-selection--auth)" not in cleaned
    assert "## Models (selection + auth)" in cleaned
    assert "octicon-mark-github" in cleaned


def test_cleanup_github_markdown_removes_contributor_avatar_gallery():
    markdown = "\n".join(
        [
            "## Community",
            "See [CONTRIBUTING.md](https://github.com/openclaw/openclaw/blob/main/CONTRIBUTING.md) for details.",
            "",
            "Thanks to all clawtributors:",
            "",
            '[![alice](https://avatars.githubusercontent.com/u/1?v=4&s=48 "alice")](https://github.com/alice)',
            "",
            '[![bob](https://avatars.githubusercontent.com/u/2?v=4&s=48 "bob")](https://github.com/bob)',
            "",
            '[![dependabot[bot]](https://avatars.githubusercontent.com/in/29110?v=4&s=48 "dependabot[bot]")](https://github.com/apps/dependabot)',
            "",
            "AI/vibe-coded PRs welcome! 🤖",
        ]
    )

    cleaned = web_save_parser.cleanup_github_markdown(markdown)

    assert "avatars.githubusercontent.com" not in cleaned
    assert "Thanks to all clawtributors:" not in cleaned
    assert "## Community" in cleaned
    assert "See [CONTRIBUTING.md]" in cleaned
    assert "AI/vibe-coded PRs welcome!" in cleaned


def test_cleanup_github_markdown_removes_badge_image_noise():
    markdown = "\n".join(
        [
            "![CI status](https://camo.githubusercontent.com/ci-badge)",
            "[![Discord](https://camo.githubusercontent.com/discord-badge)](https://discord.gg/clawd)",
            "![MIT License](https://camo.githubusercontent.com/license-badge)",
            "![Star History Chart](https://camo.githubusercontent.com/star-history)",
            "![Architecture diagram](https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/diagram.png)",
            "",
            "Intro paragraph.",
        ]
    )

    cleaned = web_save_parser.cleanup_github_markdown(markdown)

    assert "CI status" not in cleaned
    assert "Discord" not in cleaned
    assert "MIT License" not in cleaned
    assert "Star History Chart" not in cleaned
    assert "Architecture diagram" in cleaned
    assert "Intro paragraph." in cleaned


def test_cleanup_github_markdown_keeps_badge_like_line_after_intro():
    markdown = "\n".join(
        [
            "# Repo",
            "",
            "This repository explains architecture tradeoffs in detail.",
            "",
            "## Build Status Reference",
            "",
            "![CI status](https://img.shields.io/badge/ci-passing-brightgreen)",
            "",
            "The status badge above is referenced in this section.",
        ]
    )

    cleaned = web_save_parser.cleanup_github_markdown(markdown)

    assert "CI status" in cleaned
    assert "Build Status Reference" in cleaned
    assert "architecture tradeoffs" in cleaned


def test_cleanup_github_markdown_removes_star_history_outside_badge_zone():
    markdown = "\n".join(
        [
            "# Repo",
            "",
            "This repository explains architecture tradeoffs in detail.",
            "",
            "## References",
            "",
            "[![Star History Chart](https://camo.githubusercontent.com/star-history)](https://www.star-history.com/#openclaw/openclaw&type=date)",
            "",
            "Reference text that should stay.",
        ]
    )

    cleaned = web_save_parser.cleanup_github_markdown(markdown)

    assert "Star History Chart" not in cleaned
    assert "star-history.com" not in cleaned
    assert "Reference text that should stay." in cleaned


def test_cleanup_substack_markdown_removes_chrome_and_svg_controls():
    markdown = "\n".join(
        [
            "*I’m excited about the new",
            "[![](https://img.example.com/a.jpg)",
            "Codex App](https://openai.com/index/introducing-the-codex-app/).",
            "",
            "[![](https://substack-post-media.s3.amazonaws.com/public/images/hero.jpeg)",
            "<svg viewBox='0 0 24 24'><path d='M1 1'></path></svg>](https://substackcdn.com/image/fetch/$s_abc/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fhero.jpeg)",
            "",
            "[Subscribe now](https://www.ignorance.ai/subscribe)",
            "",
            "[<svg viewBox='0 0 24 24'><path d='M1 1'></path></svg>](https://substackcdn.com/image/fetch/abc)",
            "",
            "Thanks for reading Artificial Ignorance! This post is public so feel free to share it.",
            "[Share](https://www.ignorance.ai/p/foo?action=share)",
            "",
            "![](https://substack-post-media.s3.amazonaws.com/public/images/keep.jpeg)",
        ]
    )

    cleaned = web_save_parser.cleanup_substack_markdown(markdown)

    assert "[Subscribe now]" not in cleaned
    assert "[Share]" not in cleaned
    assert "<svg" not in cleaned
    assert "![](https://img.example.com/a.jpg)" not in cleaned
    assert "](https://substackcdn.com/image/fetch/" not in cleaned
    assert (
        "![](https://substack-post-media.s3.amazonaws.com/public/images/hero.jpeg)"
        in cleaned
    )
    assert "[Codex App](https://openai.com/index/introducing-the-codex-app/)" in cleaned
    assert (
        "![](https://substack-post-media.s3.amazonaws.com/public/images/keep.jpeg)"
        in cleaned
    )


def test_cleanup_substack_markdown_normalizes_footnotes_and_editor_markup():
    markdown = "\n".join(
        [
            "Main claim with citation[1](#footnote-1) and another[2](#footnote-2).",
            "",
            "### ",
            "",
            "> Quoted intro.",
            ">",
            "> Continued quote.",
            "",
            "***Editor:******Ankit Maloo blogs at** <https://ankitmaloo.com/>",
            "",
            "[1](#footnote-anchor-1)",
            "",
            "First footnote content.",
            "",
            "[2](#footnote-anchor-2)",
            "",
            "Second footnote content.",
        ]
    )

    cleaned = web_save_parser.cleanup_substack_markdown(markdown)

    assert "[^1]" in cleaned
    assert "[^2]" in cleaned
    assert "[^1]: First footnote content." in cleaned
    assert "[^2]: Second footnote content." in cleaned
    assert "#footnote-" not in cleaned
    assert "\n###\n" not in cleaned
    assert "\n>\n" not in cleaned
    assert "> Quoted intro." in cleaned
    assert "> Continued quote." in cleaned
    assert "Editor: Ankit Maloo blogs at <https://ankitmaloo.com/>" in cleaned


def test_cleanup_substack_markdown_handles_titled_proxy_linked_images():
    markdown = "\n".join(
        [
            "Before image.",
            "",
            '[![Image](https://substack-post-media.s3.amazonaws.com/public/images/cc527f70-b3e4-498b-80bb-bfa03f24dd5b_1900x1175.png "Image")',
            "",
            "<svg viewBox='0 0 24 24'><path d='M1 1'></path></svg>"
            "<svg viewBox='0 0 24 24'><path d='M2 2'></path></svg>](https://substackcdn.com/image/fetch/$s_!IOnc!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fcc527f70-b3e4-498b-80bb-bfa03f24dd5b_1900x1175.png)",
            "",
            '[![](https://substack-post-media.s3.amazonaws.com/public/images/933c53d7-43f9-455e-b4e7-2ee52f4a33ee_1565x1184.png "NotebookLM lets you conduct research reports and gather source documents (on the left), ask questions of the sources and material (the middle) and turn them into things like slide shows (on the right)")',
            "",
            "<svg viewBox='0 0 24 24'><path d='M1 1'></path></svg>](https://substackcdn.com/image/fetch/$s_!5NR5!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F933c53d7-43f9-455e-b4e7-2ee52f4a33ee_1565x1184.png)",
            "",
            "After image.",
        ]
    )

    cleaned = web_save_parser.cleanup_substack_markdown(markdown)

    assert (
        "https://substack-post-media.s3.amazonaws.com/public/images/cc527f70-b3e4-498b-80bb-bfa03f24dd5b_1900x1175.png"
        in cleaned
    )
    assert (
        "![](https://substack-post-media.s3.amazonaws.com/public/images/933c53d7-43f9-455e-b4e7-2ee52f4a33ee_1565x1184.png)"
        in cleaned
    )
    assert "substackcdn.com/image/fetch" not in cleaned
    assert "[, ask questions of the sources and material" not in cleaned
    assert "<svg" not in cleaned


def test_insert_youtube_placeholders_handles_comment_sibling():
    extracted_html = "<article><p>Anchor</p></article>"
    raw_html = """
    <html>
      <body>
        <article>
          <p>Anchor</p>
          <!-- comment -->
          <iframe src="https://www.youtube.com/embed/abcd1234"></iframe>
        </article>
      </body>
    </html>
    """
    raw_dom = lxml_html.fromstring(raw_html)
    updated = web_save_parser.insert_youtube_placeholders(
        extracted_html,
        raw_dom,
        "https://example.com/article",
    )
    assert "YOUTUBE_EMBED:abcd1234" in updated


def test_simplify_linked_images_unwraps_matching_links():
    markdown = "[![](https://example.com/img.jpg)](https://example.com/img.jpg)"
    simplified = web_save_parser.simplify_linked_images(markdown)
    assert simplified.strip() == "![](https://example.com/img.jpg)"


def test_compute_word_count_ignores_image_url_noise():
    markdown = "\n".join(
        [
            "Intro words only.",
            "[![Badge](https://img.shields.io/badge)](https://github.com/actions)",
            "![Screenshot](https://example.com/screen.png)",
            "Read [the docs](https://docs.example.com/path?q=1) and <https://example.com/raw>.",
            "Visit https://example.com/else too.",
        ]
    )

    assert web_save_parser.compute_word_count(markdown) == 9


def test_parse_url_local_frontmatter_metrics_follow_final_markdown(monkeypatch):
    words = " ".join(["word"] * 248)
    html = f"""
    <html>
      <head><title>Metrics Consistency</title></head>
      <body>
        <article>
          <p>{words}</p>
          <img src="https://example.com/dup.jpg" alt="Duplicate image"/>
          <img src="https://example.com/dup.jpg" alt="Duplicate image"/>
          <img src="https://example.com/dup.jpg" alt="Duplicate image"/>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/metrics", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/metrics")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    body = parsed.content.split("---\n", 2)[2]

    final_word_count = web_save_parser.compute_word_count(body)
    final_image_count = web_save_parser.count_images(body)

    assert final_image_count == 1
    assert data["word_count"] == final_word_count
    assert data["reading_time"] == calculate_reading_time(
        final_word_count,
        image_count=final_image_count,
    )


def test_parse_url_local_applies_github_cleanup_conservatively(monkeypatch):
    html = """
    <html>
      <head><title>GitHub Cleanup Probe</title></head>
      <body>
        <article>
          <h1>Repo</h1>
          <a href="#repo"><svg class="octicon octicon-link"></svg></a>
          <p><img alt="CI status" src="https://camo.githubusercontent.com/abc123/ci-passing"/></p>
          <p><img alt="GitHub release" src="https://camo.githubusercontent.com/def456/release"/></p>
          <p><img alt="Architecture diagram" src="https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/diagram.png"/></p>
          <p>This repository contains useful implementation details.</p>
          <h2>Later Section</h2>
          <p><img alt="CI status" src="https://camo.githubusercontent.com/xyz999/ci-stable"/></p>
          <p>In this section we intentionally reference the status badge.</p>
          <h2>Community</h2>
          <p><a href="https://www.star-history.com/#openclaw/openclaw"><img alt="Star History Chart" src="https://camo.githubusercontent.com/star-history"/></a></p>
          <p><a href="https://github.com/apps/dependabot"><img alt="dependabot[bot]" src="https://avatars.githubusercontent.com/in/29110?v=4&s=48"/></a></p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://github.com/openclaw/openclaw", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("github.com/openclaw/openclaw")

    assert "octicon-link" not in parsed.content
    assert "GitHub release" not in parsed.content
    assert "Architecture diagram" in parsed.content
    assert "This repository contains useful implementation details." in parsed.content
    assert "Later Section" in parsed.content
    assert parsed.content.count("CI status") == 1
    assert "Star History Chart" not in parsed.content
    assert "star-history.com" not in parsed.content
    assert "avatars.githubusercontent.com" not in parsed.content
    assert "dependabot[bot]" not in parsed.content


def test_parse_url_local_force_rendering(monkeypatch):
    html = "<html><body><div class='force'>Placeholder</div></body></html>"
    rendered = "<html><head><title>Rendered</title></head><body><article>Rendered body</article></body></html>"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/render", False

    def fake_render(
        url: str, *, timeout: int = 30000, wait_for=None, wait_until="networkidle"
    ):
        return rendered, "https://example.com/rendered"

    rule = web_save_parser.Rule(
        id="force-render",
        phase="pre",
        priority=0,
        trigger={"dom": {"any": [".force"]}},
        rendering={"mode": "force"},
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "render_html_with_playwright", fake_render)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    parsed = web_save_parser.parse_url_local("example.com/render")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert data["used_js_rendering"] is True
    assert parsed.title == "Rendered"


def test_parse_url_local_force_rendering_skips_when_playwright_fails(monkeypatch):
    html = """
    <html>
      <head><title>Force Render Fallback</title></head>
      <body>
        <article>
          <div class="force">Placeholder</div>
          <p>Local parser should keep this when rendering fails.</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/render", False

    def fake_render(
        url: str, *, timeout: int = 30000, wait_for=None, wait_until="networkidle"
    ):
        raise RuntimeError("Browser executable missing")

    rule = web_save_parser.Rule(
        id="force-render",
        phase="pre",
        priority=0,
        trigger={"dom": {"any": [".force"]}},
        rendering={"mode": "force"},
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "render_html_with_playwright", fake_render)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    parsed = web_save_parser.parse_url_local("example.com/render")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["used_js_rendering"] is False
    assert "Local parser should keep this when rendering fails." in parsed.content


def test_parse_url_local_auto_rendering_skips_when_playwright_fails(monkeypatch):
    html = """
    <html>
      <head><title>Auto Render Fallback</title></head>
      <body>
        <article>
          <p>Local parser should keep this when auto rendering fails.</p>
          <a href="https://www.youtube.com/embed/abc123xyzAA">video</a>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/auto-render", False

    def fake_render(
        url: str, *, timeout: int = 30000, wait_for=None, wait_until="networkidle"
    ):
        raise RuntimeError("Browser executable missing")

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "render_html_with_playwright", fake_render)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    parsed = web_save_parser.parse_url_local("example.com/auto-render")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["used_js_rendering"] is False
    assert "Local parser should keep this when auto rendering fails." in parsed.content


def test_parse_url_local_includes_hero_image(monkeypatch):
    html = """
    <html>
      <head>
        <title>Image Test</title>
        <meta property="og:image" content="https://images.example.com/hero.jpg"/>
      </head>
      <body>
        <article><p>Content body</p></article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "![Image Test](https://images.example.com/hero.jpg)" in parsed.content


def test_parse_url_local_dedupes_hero_image(monkeypatch):
    html = """
    <html>
      <head>
        <title>Image Test</title>
        <meta property="og:image" content="https://images.example.com/hero.jpg"/>
      </head>
      <body>
        <article>
          <img src="https://images.example.com/hero.jpg" alt="Hero"/>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert parsed.content.count("https://images.example.com/hero.jpg") == 1


def test_parse_url_local_dedupes_encoded_hero_image(monkeypatch):
    html = """
    <html>
      <head>
        <title>Substack Test</title>
        <meta property="og:image" content="https://substackcdn.com/image/fetch/$s_abc,w_1200/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fhero.webp"/>
      </head>
      <body>
        <article>
          <img src="https://substackcdn.com/image/fetch/$s_def,w_1456/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fhero.webp"/>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert (
        parsed.content.count(
            "substack-post-media.s3.amazonaws.com/public/images/hero.webp"
        )
        == 1
    )


def test_dedupe_markdown_images_handles_linked_title():
    markdown = (
        "![Hero](https://example.com/hero.png)\n\n"
        '[![](https://example.com/hero.png "Title")](https://example.com/hero.png)\n'
    )
    deduped = web_save_parser.dedupe_markdown_images(markdown)
    assert deduped.count("hero.png") == 1
    assert "[!]" not in deduped
    assert "![Hero]" in deduped


def test_dedupe_markdown_images_separates_adjacent_images():
    markdown = (
        "![](https://example.com/a.png)![](https://example.com/b.png)\n"
        "[![](https://example.com/c.png)](https://example.com/c.png)"
        "[![](https://example.com/d.png)](https://example.com/d.png)\n"
    )
    deduped = web_save_parser.dedupe_markdown_images(markdown)
    assert "\n\n![](https://example.com/b.png)" in deduped
    assert "\n\n[![](https://example.com/d.png)]" in deduped


def test_dedupe_markdown_blocks_removes_repeated_sections():
    markdown = "\n\n".join(
        [
            "Chess relies on reasoning. Werewolf relies on social deduction. Poker introduces a new dimension: risk management.",
            "## Watch the action",
            "Tune in to the three daily livestreams at 9:30 AM PT at [kaggle.com/game-arena](https://www.kaggle.com/game-arena).",
            "## Explore the arena",
            "Check it out at [kaggle.com/game-arena](http://kaggle.com/game-arena).",
            "Chess relies on reasoning. Werewolf relies on social deduction. Poker introduces a new dimension: risk management.",
            "## Watch the action",
            "Tune in to the three daily livestreams at 9:30 AM PT at [kaggle.com/game-arena](https://www.kaggle.com/game-arena).",
            "## Explore the arena",
            "Check it out at [kaggle.com/game-arena](http://kaggle.com/game-arena).",
        ]
    )
    deduped = web_save_parser.dedupe_markdown_blocks(markdown)
    assert (
        deduped.count(
            "Chess relies on reasoning. Werewolf relies on social deduction. Poker introduces a new dimension: risk management."
        )
        == 1
    )
    assert deduped.count("## Watch the action") == 1
    assert deduped.count("## Explore the arena") == 1
    assert (
        deduped.count(
            "Check it out at [kaggle.com/game-arena](http://kaggle.com/game-arena)."
        )
        == 1
    )


def test_normalize_image_captions_moves_figcaption():
    html = """
    <figure>
      <img src="https://example.com/image.png" alt="Alt"/>
      <figcaption>Caption text</figcaption>
    </figure>
    """
    normalized = web_save_parser.normalize_image_captions(html)
    soup = BeautifulSoup(normalized, "html.parser")
    img = soup.find("img")
    assert img is not None
    assert img.get("title") == "Caption text"
    assert soup.find("figcaption") is None


def test_normalize_image_captions_from_gallery_data_attrs():
    html = """
    <div data-attrs='{"gallery":{"caption":"Gallery caption"}}'>
      <img src="https://example.com/gallery.png" alt=""/>
      <img src="https://example.com/gallery-last.png" alt=""/>
    </div>
    """
    normalized = web_save_parser.normalize_image_captions(html)
    soup = BeautifulSoup(normalized, "html.parser")
    imgs = soup.find_all("img")
    assert len(imgs) == 2
    assert imgs[0].get("title") is None
    assert imgs[-1].get("title") == "Gallery caption"


def test_normalize_image_captions_from_gallery_sources_after_node():
    html = """
    <div data-attrs='{"gallery":{"caption":"Gallery caption","images":[{"src":"https://example.com/one.png"},{"src":"https://example.com/two.png"}]}}'></div>
    <p>Text</p>
    <img src="https://example.com/one.png" alt=""/>
    <img src="https://example.com/two.png" alt=""/>
    """
    normalized = web_save_parser.normalize_image_captions(html)
    soup = BeautifulSoup(normalized, "html.parser")
    imgs = soup.find_all("img")
    assert len(imgs) == 2
    assert imgs[0].get("title") is None
    assert imgs[-1].get("title") == "Gallery caption"


def test_normalize_image_captions_moves_gallery_caption_to_last_image():
    html = """
    <figure>
      <img src="https://example.com/one.png" title="Gallery caption"/>
      <figcaption>Gallery caption</figcaption>
    </figure>
    <img src="https://example.com/two.png" alt=""/>
    <div data-attrs='{"gallery":{"caption":"Gallery caption","images":[{"src":"https://example.com/one.png"},{"src":"https://example.com/two.png"}]}}'></div>
    """
    normalized = web_save_parser.normalize_image_captions(html)
    soup = BeautifulSoup(normalized, "html.parser")
    imgs = soup.find_all("img")
    assert len(imgs) == 2
    assert imgs[0].get("title") is None
    assert imgs[-1].get("title") == "Gallery caption"


def test_parse_url_local_dedupes_wp_com_proxy_images(monkeypatch):
    html = """
    <html>
      <head>
        <title>WP Test</title>
        <meta property="og:image" content="https://onlydeadfish.co.uk/wp-content/uploads/2026/01/Corporate-carpets.png"/>
      </head>
      <body>
        <article>
          <img src="https://i0.wp.com/onlydeadfish.co.uk/wp-content/uploads/2026/01/Corporate-carpets.png?resize=1000%2C735&ssl=1"/>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://onlydeadfish.co.uk/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("onlydeadfish.co.uk/article")
    assert parsed.content.count("Corporate-carpets.png") == 1


def test_wrap_gallery_blocks_builds_html_gallery():
    markdown = "\n".join(
        [
            "![](https://example.com/one.png)",
            "",
            '![](https://example.com/two.png "Gallery caption")',
        ]
    )
    wrapped = web_save_parser.wrap_gallery_blocks(markdown)
    assert "<figure" in wrapped
    assert "image-gallery" in wrapped
    assert 'data-caption="Gallery caption"' in wrapped
    assert "https://example.com/one.png" in wrapped
    assert "https://example.com/two.png" in wrapped


def test_parse_url_local_inserts_youtube_link_after_anchor(monkeypatch):
    html = """
    <html>
      <head>
        <title>Inline Video</title>
      </head>
      <body>
        <article>
          <p>Intro text.</p>
          <p>Video explains things clearly.</p>
          <iframe src="https://www.youtube.com/embed/abc123"></iframe>
          <p>More text follows.</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/video", False

    def skip_placeholder(article_html: str, _raw_dom, _base_url: str) -> str:
        return article_html

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "insert_youtube_placeholders", skip_placeholder
    )

    parsed = web_save_parser.parse_url_local("example.com/video")
    content_lines = parsed.content.splitlines()
    anchor_index = next(
        index
        for index, line in enumerate(content_lines)
        if "Video explains things clearly." in line
    )
    youtube_index = next(
        index
        for index, line in enumerate(content_lines)
        if "https://www.youtube.com/watch?v=abc123" in line
    )
    after_index = next(
        index
        for index, line in enumerate(content_lines)
        if "More text follows." in line
    )

    assert anchor_index < youtube_index < after_index


def test_parse_url_local_inserts_youtube_from_jsonld(monkeypatch):
    html = """
    <html>
      <head>
        <title>JSON-LD Video</title>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "NewsArticle",
            "articleBody": "Intro text.\\n[Media: https://www.youtube.com/watch?v=abc123]\\nMore text."
          }
        </script>
      </head>
      <body>
        <article>
          <p>Intro text.</p>
          <p>More text.</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/video", False

    def skip_placeholder(article_html: str, _raw_dom, _base_url: str) -> str:
        return article_html

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "insert_youtube_placeholders", skip_placeholder
    )

    parsed = web_save_parser.parse_url_local("example.com/video")
    content_lines = parsed.content.splitlines()
    anchor_index = next(
        index for index, line in enumerate(content_lines) if "Intro text." in line
    )
    youtube_index = next(
        index
        for index, line in enumerate(content_lines)
        if "https://www.youtube.com/watch?v=abc123" in line
    )
    after_index = next(
        index for index, line in enumerate(content_lines) if "More text." in line
    )

    assert anchor_index < youtube_index < after_index


def test_parse_url_local_includes_verge_gallery_images(monkeypatch):
    html = """
    <html>
      <head>
        <title>Verge Gallery</title>
      </head>
      <body>
        <div class="duet--article--gallery">
          <a href="https://platform.theverge.com/wp-content/uploads/a.jpg">
            <img src="https://platform.theverge.com/wp-content/uploads/a.jpg"/>
          </a>
          <a href="https://platform.theverge.com/wp-content/uploads/b.jpg">
            <img src="https://platform.theverge.com/wp-content/uploads/b.jpg"/>
          </a>
        </div>
        <article>
          <p>Gallery content.</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.theverge.com/news/123", False

    web_save_parser.get_rule_engine.cache_clear()
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("https://www.theverge.com/news/123")
    assert "https://platform.theverge.com/wp-content/uploads/a.jpg" in parsed.content
    assert "https://platform.theverge.com/wp-content/uploads/b.jpg" in parsed.content


def test_parse_url_local_handles_comment_root(monkeypatch):
    html = """
    <html>
      <head><title>Comment Root</title></head>
      <body><!-- comment --><article><p>Content body</p></article></body>
    </html>
    """

    class FakeDocument:
        def __init__(self, _html: str) -> None:
            pass

        def summary(self, html_partial: bool = True) -> str:
            return "<!--comment--><article><p>Content body</p></article>"

        def short_title(self) -> str:
            return ""

        def title(self) -> str:
            return "Comment Root"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "ReadabilityDocument", FakeDocument)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "Content body" in parsed.content


def test_parse_url_local_strips_control_chars_before_readability(monkeypatch):
    html = """
    <html>
      <head><title>Control Chars</title></head>
      <body><article>Content\x00body</article></body>
    </html>
    """

    class FakeDocument:
        def __init__(self, _html: str) -> None:
            assert "\x00" not in _html

        def summary(self, html_partial: bool = True) -> str:
            return "<article>Content body</article>"

        def short_title(self) -> str:
            return ""

        def title(self) -> str:
            return "Control Chars"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "ReadabilityDocument", FakeDocument)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "Content body" in parsed.content


def test_wrap_gallery_blocks_ignores_single_captioned_image():
    markdown = '![](https://example.com/one.png "Caption")'
    wrapped = web_save_parser.wrap_gallery_blocks(markdown)
    assert wrapped.strip() == markdown


def test_filter_non_content_images_removes_thumbnail_query():
    html = """
    <div>
      <img src="https://example.com/thumb.jpg?w=290&h=145&crop=1" />
      <img src="https://example.com/hero.jpg?w=1400&h=800" />
    </div>
    """
    filtered = web_save_parser.filter_non_content_images(html)
    soup = BeautifulSoup(filtered, "html.parser")
    imgs = [img.get("src") for img in soup.find_all("img")]
    assert "https://example.com/thumb.jpg?w=290&h=145&crop=1" not in imgs
    assert "https://example.com/hero.jpg?w=1400&h=800" in imgs


def test_parse_url_local_normalizes_lazy_images(monkeypatch):
    html = """
    <html>
      <head><title>Lazy</title></head>
      <body>
        <article>
          <img data-src="/images/lazy.jpg" alt="Lazy"/>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "![Lazy](https://example.com/images/lazy.jpg)" in parsed.content


def test_parse_url_local_tracks_youtube_embed(monkeypatch):
    html = """
    <html>
      <head><title>Video</title></head>
      <body>
        <article>
          <iframe src="https://www.youtube.com/embed/abc123"></iframe>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "[YouTube](https://www.youtube.com/watch?v=abc123)" in parsed.content


def test_parse_url_local_normalizes_youtube_title_suffix(monkeypatch):
    html = """
    <html>
      <head><title>Recovered Video Title - YouTube</title></head>
      <body><article><p>Content body</p></article></body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.youtube.com/watch?v=abc123xyzAA", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local(
        "https://www.youtube.com/watch?v=abc123xyzAA"
    )
    assert parsed.title == "Recovered Video Title"


def test_parse_url_local_collapses_youtube_shorts_footer_chrome(monkeypatch):
    html = """
    <html>
      <head><title>Recovered Shorts Title - YouTube</title></head>
      <body>
        <article>
          <svg class="external-icon"></svg>
          <a href="https://www.youtube.com/about/">About</a>
          <a href="https://www.youtube.com/t/privacy">Privacy</a>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.youtube.com/shorts/Kg3VeW7yEyY", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local(
        "https://www.youtube.com/watch?v=Kg3VeW7yEyY"
    )
    assert "[YouTube](https://www.youtube.com/watch?v=Kg3VeW7yEyY)" in parsed.content
    assert "https://www.youtube.com/about/" not in parsed.content


def test_parse_url_local_uses_youtube_duration_for_reading_time(monkeypatch):
    html = """
    <html>
      <head>
        <title>Recovered Video Title - YouTube</title>
        <meta itemprop="duration" content="PT3M34S"/>
      </head>
      <body><article><p>Content body</p></article></body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.youtube.com/watch?v=abc123xyzAA", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    parsed = web_save_parser.parse_url_local(
        "https://www.youtube.com/watch?v=abc123xyzAA"
    )
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert data["reading_time"] == "4 mins"


def test_parse_url_local_uses_youtube_length_seconds_fallback(monkeypatch):
    html = """
    <html>
      <head><title>Recovered Video Title - YouTube</title></head>
      <body>
        <script>
          var ytp = {"videoDetails":{"lengthSeconds":"125"}};
        </script>
        <article><p>Content body</p></article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.youtube.com/watch?v=abc123xyzAA", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )

    parsed = web_save_parser.parse_url_local(
        "https://www.youtube.com/watch?v=abc123xyzAA"
    )
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert data["reading_time"] == "3 mins"


def test_parse_url_local_tracks_youtube_embed_from_raw_html(monkeypatch):
    html = """
    <html>
      <head><title>Video</title></head>
      <body>
        <div class="video">
          <iframe src="https://www.youtube.com/embed/raw123"></iframe>
        </div>
        <article>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    class DummyDocument:
        def __init__(self, _html: str) -> None:
            pass

        def summary(self, html_partial: bool = True) -> str:
            return "<article><p>Content body</p></article>"

        def short_title(self) -> str:
            return "Video"

        def title(self) -> str:
            return "Video"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "ReadabilityDocument", DummyDocument)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "[YouTube](https://www.youtube.com/watch?v=raw123)" in parsed.content


def test_parse_url_local_tracks_youtube_embed_from_escaped_raw_html(monkeypatch):
    html = """
    <html>
      <head><title>Video</title></head>
      <body>
        <script>
          var data = {\"embed\": \"https:\\/\\/www.youtube.com\\/embed\\/esc123\"};
        </script>
        <article>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    class DummyDocument:
        def __init__(self, _html: str) -> None:
            pass

        def summary(self, html_partial: bool = True) -> str:
            return "<article><p>Content body</p></article>"

        def short_title(self) -> str:
            return "Video"

        def title(self) -> str:
            return "Video"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "ReadabilityDocument", DummyDocument)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "[YouTube](https://www.youtube.com/watch?v=esc123)" in parsed.content


def test_replace_youtube_placeholders_handles_escaped_underscores():
    markdown, ids = web_save_parser.replace_youtube_placeholders(
        "YOUTUBE\\_EMBED:I44\\_zbEwz\\_w"
    )
    assert markdown.strip() == "[YouTube](https://www.youtube.com/watch?v=I44_zbEwz_w)"
    assert "I44_zbEwz_w" in ids


def test_parse_url_local_filters_decorative_images(monkeypatch):
    html = """
    <html>
      <head><title>Decorative</title></head>
      <body>
        <article>
          <img src="/logo.png" class="site-logo" width="32" height="32" alt="Logo"/>
          <img src="/images/story.jpg" alt="Story"/>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "logo.png" not in parsed.content
    assert "![Story](https://example.com/images/story.jpg)" in parsed.content


def test_parse_url_local_normalizes_relative_links(monkeypatch):
    html = """
    <html>
      <head><title>Links</title></head>
      <body>
        <article>
          <p><a href="/relative/path">Read more</a></p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "[Read more](https://example.com/relative/path)" in parsed.content


def test_parse_url_local_dedupes_images(monkeypatch):
    html = """
    <html>
      <head><title>Dupes</title></head>
      <body>
        <article>
          <img src="/images/dup.jpg" alt="Dup"/>
          <img src="/images/dup.jpg" alt="Dup Again"/>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert parsed.content.count("images/dup.jpg") == 1


def test_parse_url_local_removes_short_mark_highlights(monkeypatch):
    html = """
    <html>
      <head><title>Marks</title></head>
      <body>
        <article>
          <p><mark>One</mark> <mark>Two</mark> <mark>Three</mark></p>
          <p><mark>Four</mark> <mark>Five</mark> <mark>Six</mark></p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "<mark>" not in parsed.content


def test_parse_url_local_keeps_meaningful_marks(monkeypatch):
    html = """
    <html>
      <head><title>Marks</title></head>
      <body>
        <article>
          <p><mark>This is a long highlighted phrase that should stay.</mark></p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "<mark>" in parsed.content


def test_parse_url_local_removes_icon_links_in_nav(monkeypatch):
    html = """
    <html>
      <head><title>Icons</title></head>
      <body>
        <article>
          <nav><a href="#"><svg></svg></a></nav>
          <p>Content body</p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "<nav>" in parsed.content
    assert "<svg" not in parsed.content


def test_parse_url_local_keeps_inline_icon_links(monkeypatch):
    html = """
    <html>
      <head><title>Icons</title></head>
      <body>
        <article>
          <p><a href="#"><svg></svg>Details</a></p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/article", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "<svg" in parsed.content


def test_fetch_html_falls_back_to_playwright_on_forbidden(monkeypatch):
    class FakeResponse:
        def __init__(self):
            self.status_code = 403
            self.url = "https://example.com/blocked"

        def raise_for_status(self):
            raise web_save_parser.requests.HTTPError(response=self)

    def fake_get(url: str, headers=None, timeout: int = 30):
        return FakeResponse()

    def fake_render(
        url: str, *, timeout: int = 30000, wait_for=None, wait_until="networkidle"
    ):
        return "<html><body>Rendered</body></html>", "https://example.com/allowed"

    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)
    monkeypatch.setattr(web_save_parser, "render_html_with_playwright", fake_render)

    html, final_url, used_js_rendering = web_save_parser.fetch_html(
        "https://example.com/blocked"
    )
    assert "Rendered" in html
    assert final_url == "https://example.com/allowed"
    assert used_js_rendering is True


def test_fetch_html_prefers_utf8_when_server_defaults_to_latin1(monkeypatch):
    class FakeResponse:
        def __init__(self):
            self.status_code = 200
            self.url = "https://example.com/page"
            self.encoding = "ISO-8859-1"
            self.content = (
                "<html><body>What Apple can’t offer gamers.</body></html>".encode(
                    "utf-8"
                )
            )
            self.text = self.content.decode("latin-1")

        def raise_for_status(self):
            return None

    def fake_get(url: str, headers=None, timeout: int = 30):
        return FakeResponse()

    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)

    html, final_url, used_js_rendering = web_save_parser.fetch_html(
        "https://example.com/page"
    )
    assert "can’t" in html
    assert "canât" not in html
    assert final_url == "https://example.com/page"
    assert used_js_rendering is False


def test_fetch_html_uses_declared_encoding_when_utf8_decode_fails(monkeypatch):
    class FakeResponse:
        def __init__(self):
            self.status_code = 200
            self.url = "https://example.com/page"
            self.encoding = "windows-1252"
            self.content = b"<html><body>caf\xe9</body></html>"
            self.text = self.content.decode("windows-1252")

        def raise_for_status(self):
            return None

    def fake_get(url: str, headers=None, timeout: int = 30):
        return FakeResponse()

    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)

    html, final_url, used_js_rendering = web_save_parser.fetch_html(
        "https://example.com/page"
    )
    assert "café" in html
    assert final_url == "https://example.com/page"
    assert used_js_rendering is False


def test_parse_url_local_returns_paywall_message(monkeypatch):
    html = """
    <html>
      <head><title>Paywalled</title></head>
      <body>
        <div class="paywall">Subscribe to read</div>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://nytimes.com/paywall", False

    def fake_markdown(_html: str) -> str:
        return ""

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "html_to_markdown", fake_markdown)

    parsed = web_save_parser.parse_url_local("nytimes.com/paywall")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["paywalled"] is True
    assert data["truncated"] is False
    assert "Unable to save content" in parsed.content


def test_parse_url_local_paywall_preserves_preview_when_available(monkeypatch):
    html = """
    <html>
      <head><title>Paywalled Story</title></head>
      <body>
        <article>
          <h1>Paywalled Story</h1>
          <p>This is the opening preview paragraph that should still be saved.</p>
          <p>This is a second preview paragraph with useful context.</p>
          <div class="paywall">Subscribe to continue reading</div>
        </article>
      </body>
    </html>
    """

    class FakeDocument:
        def __init__(self, _html: str) -> None:
            pass

        def summary(self, html_partial: bool = True) -> str:
            return (
                "<article>"
                "<h1>Paywalled Story</h1>"
                "<p>This is the opening preview paragraph that should still be saved.</p>"
                "<p>This is a second preview paragraph with useful context.</p>"
                "<div class='paywall'>Subscribe to continue reading</div>"
                "</article>"
            )

        def short_title(self) -> str:
            return "Paywalled Story"

        def title(self) -> str:
            return "Paywalled Story"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/paywall", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "ReadabilityDocument", FakeDocument)
    monkeypatch.setattr(web_save_parser, "html_to_markdown", lambda _html: "")

    parsed = web_save_parser.parse_url_local("example.com/paywall")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["paywalled"] is True
    assert data["truncated"] is True
    assert "Warning: This article appears truncated." in parsed.content
    assert "opening preview paragraph" in parsed.content
    assert "second preview paragraph" in parsed.content


def test_parse_url_local_paywall_marks_anti_bot_block(monkeypatch):
    html = """
    <html>
      <head><title>wsj.com</title></head>
      <body>
        <script>var dd={host:'geo.captcha-delivery.com'}</script>
        <p>Please enable JS and disable any ad blocker</p>
      </body>
    </html>
    """

    class FakeDocument:
        def __init__(self, _html: str) -> None:
            pass

        def summary(self, html_partial: bool = True) -> str:
            return "<div></div>"

        def short_title(self) -> str:
            return "wsj.com"

        def title(self) -> str:
            return "wsj.com"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.wsj.com/tech/ai/story-id", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "ReadabilityDocument", FakeDocument)
    monkeypatch.setattr(web_save_parser, "html_to_markdown", lambda _html: "")

    parsed = web_save_parser.parse_url_local("https://www.wsj.com/tech/ai/story-id")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["paywalled"] is True
    assert data["truncated"] is False
    assert data["anti_bot_blocked"] is True
    assert "anti-bot challenge page" in parsed.content


def test_parse_url_local_uses_substack_api(monkeypatch):
    html = """
    <html>
      <head><title>Custom Domain Post</title></head>
      <body>
        <div>Article shell</div>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/p/substack-post", False

    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "title": "Substack Title",
                "post_date": "2025-01-02T12:00:00Z",
                "canonical_url": "https://example.com/p/substack-post",
                "body_html": "<p>Full body</p>",
            }

    def fake_get(url: str, headers=None, timeout: int = 30):
        return FakeResponse()

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)

    parsed = web_save_parser.parse_url_local("example.com/p/substack-post")
    assert "Full body" in parsed.content


def test_parse_url_local_applies_substack_host_rules_on_custom_domain(monkeypatch):
    html = """
    <html>
      <head><title>Custom Substack</title></head>
      <body>
        <article><p>Fallback body</p></article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.ignorance.ai/p/custom-domain-post", False

    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "title": "Custom Substack",
                "canonical_url": "https://www.ignorance.ai/p/custom-domain-post",
                "body_html": (
                    "<div class='post-footer'>Subscribe now</div>"
                    "<p>Primary article body</p>"
                ),
            }

    def fake_get(url: str, headers=None, timeout: int = 30):
        return FakeResponse()

    engine = web_save_parser.RuleEngine(
        rules=[
            web_save_parser.Rule(
                id="substack-cleanup",
                phase="post",
                priority=0,
                trigger={"host": {"ends_with": "substack.com"}},
                remove=[".post-footer"],
            )
        ]
    )

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)
    monkeypatch.setattr(
        web_save_parser,
        "_favicon_exists",
        lambda url, timeout=8: False,
    )
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)

    parsed = web_save_parser.parse_url_local("ignorance.ai/p/custom-domain-post")

    assert "Primary article body" in parsed.content
    assert "Subscribe now" not in parsed.content


def test_parse_url_local_cleans_substack_custom_domain_markdown_chrome(monkeypatch):
    html = """
    <html>
      <head><title>Custom Substack</title></head>
      <body>
        <article><p>Fallback body</p></article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.ignorance.ai/p/custom-domain-post", False

    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "title": "Custom Substack",
                "canonical_url": "https://www.ignorance.ai/p/custom-domain-post",
                "body_html": (
                    "<p>I’m excited about the new "
                    "<a href='https://openai.com/index/introducing-the-codex-app/'>"
                    "<img src='https://substack-post-media.s3.amazonaws.com/public/images/inline.jpeg'/>"
                    "Codex App</a>.</p>"
                    "<p><a href='https://substackcdn.com/image/fetch/$s_abc/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fhero.jpeg'>"
                    "<img src='https://substack-post-media.s3.amazonaws.com/public/images/hero.jpeg'/>"
                    "<svg viewBox='0 0 24 24'><path d='M1 1'></path></svg>"
                    "</a></p>"
                    "<p><a href='https://www.ignorance.ai/subscribe'>Subscribe now</a></p>"
                    "<p><a href='https://substackcdn.com/image/fetch/abc'>"
                    "<svg viewBox='0 0 24 24'><path d='M1 1'></path></svg>"
                    "</a></p>"
                    "<p>Thanks for reading Artificial Ignorance! This post is public so feel free to share it.</p>"
                    "<p><a href='https://www.ignorance.ai/p/custom-domain-post?action=share'>Share</a></p>"
                ),
            }

    def fake_get(url: str, headers=None, timeout: int = 30):
        return FakeResponse()

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)
    monkeypatch.setattr(
        web_save_parser,
        "_favicon_exists",
        lambda url, timeout=8: False,
    )

    parsed = web_save_parser.parse_url_local("ignorance.ai/p/custom-domain-post")

    assert "<svg" not in parsed.content
    assert "Subscribe now" not in parsed.content
    assert "\n[Share](" not in parsed.content
    assert "new ![](" not in parsed.content
    assert "](https://substackcdn.com/image/fetch/" not in parsed.content
    assert "[](https://substackcdn.com/image/fetch/" not in parsed.content


def test_parse_url_local_cleans_substack_custom_domain_when_api_unavailable(
    monkeypatch,
):
    html = """
    <html>
      <head>
        <title>Custom Substack</title>
        <meta name="substack:publication_id" content="12345" />
      </head>
      <body>
        <article>
          <p>I’m excited about the new
            <a href="https://openai.com/index/introducing-the-codex-app/">
              <img src="https://substack-post-media.s3.amazonaws.com/public/images/inline.jpeg"/>
              Codex App
            </a>.
          </p>
          <p>
            <a href="https://substackcdn.com/image/fetch/$s_abc/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fhero.jpeg">
              <img src="https://substack-post-media.s3.amazonaws.com/public/images/hero.jpeg"/>
              <svg viewBox="0 0 24 24"><path d="M1 1"></path></svg>
            </a>
          </p>
          <p><a href="https://www.ignorance.ai/subscribe">Subscribe now</a></p>
          <p>Thanks for reading Artificial Ignorance! This post is public so feel free to share it.</p>
          <p><a href="https://www.ignorance.ai/p/custom-domain-post?action=share">Share</a></p>
        </article>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://www.ignorance.ai/p/custom-domain-post", False

    def fake_get(url: str, headers=None, timeout: int = 30):
        raise web_save_parser.requests.RequestException("Substack API unavailable")

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)
    monkeypatch.setattr(
        web_save_parser,
        "_favicon_exists",
        lambda url, timeout=8: False,
    )

    parsed = web_save_parser.parse_url_local("ignorance.ai/p/custom-domain-post")

    assert "<svg" not in parsed.content
    assert "\n[Subscribe now](" not in parsed.content
    assert "\n[Share](" not in parsed.content
    assert "new ![](" not in parsed.content
    assert "](https://substackcdn.com/image/fetch/" not in parsed.content
    assert "[](https://substackcdn.com/image/fetch/" not in parsed.content
    assert (
        "![](https://substack-post-media.s3.amazonaws.com/public/images/hero.jpeg)"
        in parsed.content
    )


def test_parse_url_local_scopes_readability_with_selector_override(monkeypatch):
    html = """
    <html>
      <head><title>Raw</title></head>
      <body>
        <div class="target"><p>Raw Content</p></div>
      </body>
    </html>
    """

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/raw", False

    calls = {"summary": False, "html": None}

    class FakeDocument:
        def __init__(self, _html: str):
            calls["html"] = _html

        def summary(self, html_partial: bool = True):
            calls["summary"] = True
            return calls["html"]

        def short_title(self):
            return "Raw"

        def title(self):
            return "Raw"

    rule = web_save_parser.Rule(
        id="raw-override",
        phase="pre",
        priority=0,
        trigger={"dom": {"any": [".target"]}},
        selector_overrides={"article": ".target"},
    )
    engine = web_save_parser.RuleEngine([rule])
    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(web_save_parser, "get_rule_engine", lambda: engine)
    monkeypatch.setattr(web_save_parser, "ReadabilityDocument", FakeDocument)

    parsed = web_save_parser.parse_url_local("example.com/raw")
    assert calls["summary"] is True
    assert "Raw Content" in parsed.content
