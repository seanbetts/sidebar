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
        return html, "https://example.com/article?utm=ignored"

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
        return html, "https://example.com/article"

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


def test_parse_url_local_discard_rule(monkeypatch):
    html = "<html><head><title>Discard Me</title></head><body><article>Skip</article></body></html>"

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://example.com/discard"

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
        return html, "https://example.com/include"

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
        return html, "https://example.com/render"

    def fake_render(url: str, *, timeout: int = 30000, wait_for=None):
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
        return html, "https://example.com/article"

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "![Image Test](https://images.example.com/hero.jpg)" in parsed.content
