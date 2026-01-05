"""Tests for the web-save local parser."""
from datetime import datetime, timezone

from api.services import web_save_parser


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

    parsed = web_save_parser.parse_url_local("example.com/article")

    assert parsed.title == "Svelte Example Article"
    assert parsed.source == "https://example.com/article"
    assert parsed.published_at == datetime(2025, 1, 1, 12, 0, tzinfo=timezone.utc)
    assert parsed.content.startswith("---\n")
    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)

    assert data["title"] == "Svelte Example Article"
    assert data["author"] == "Jane Doe"
    assert data["published_date"] == "2025-01-01T12:00:00+00:00"
    assert data["domain"] == "example.com"
    assert data["reading_time"]
    assert "svelte" in data["tags"]


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

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert parsed.title == "Override Title"
    assert parsed.published_at == datetime(2024, 12, 31, 10, 0, tzinfo=timezone.utc)


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
    html = "<html><body><div class='target'></div><p class='move'>Move</p></body></html>"
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
                    {"op": "set_attr", "selector": ".target", "attr": "data-test", "value": "ok"},
                ],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    cleaned = engine.apply_rules(html, matched)
    assert "data-test=\"ok\"" in cleaned
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
                    {"op": "group_siblings", "selector": ".cap", "wrapper_tag": "div", "class": "caps"},
                ],
            )
        ]
    )

    matched = engine.match_rules("https://example.com", html, phase="post")
    cleaned = engine.apply_rules(html, matched)
    assert "class=\"caps\"" in cleaned


def test_rule_engine_actions_remove_children():
    html = "<html><body><div class='box'><p>Remove me</p></div><p>Keep</p></body></html>"
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


def test_parse_url_local_force_rendering(monkeypatch):
    html = "<html><body><div class='force'>Placeholder</div></body></html>"
    rendered = "<html><head><title>Rendered</title></head><body><article>Rendered body</article></body></html>"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/render", False

    def fake_render(url: str, *, timeout: int = 30000, wait_for=None, wait_until="networkidle"):
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

    def fake_render(url: str, *, timeout: int = 30000, wait_for=None, wait_until="networkidle"):
        return "<html><body>Rendered</body></html>", "https://example.com/allowed"

    monkeypatch.setattr(web_save_parser.requests, "get", fake_get)
    monkeypatch.setattr(web_save_parser, "render_html_with_playwright", fake_render)

    html, final_url, used_js_rendering = web_save_parser.fetch_html(
        "https://example.com/blocked"
    )
    assert "Rendered" in html
    assert final_url == "https://example.com/allowed"
    assert used_js_rendering is True


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
    assert "Unable to save content" in parsed.content


def test_parse_url_local_uses_substack_api(monkeypatch):
    html = """
    <html>
      <head><title>Substack</title></head>
      <body>
        <div>substack</div>
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
    monkeypatch.setattr(web_save_parser, "Document", FakeDocument)

    parsed = web_save_parser.parse_url_local("example.com/raw")
    assert calls["summary"] is True
    assert "Raw Content" in parsed.content
