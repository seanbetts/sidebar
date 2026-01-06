"""Tests for the web-save local parser."""
from datetime import datetime, timezone

from bs4 import BeautifulSoup
from api.services import web_save_parser
from api.services import web_save_includes
from lxml import html as lxml_html


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


def test_simplify_linked_images_unwraps_matching_links():
    markdown = "[![](https://example.com/img.jpg)](https://example.com/img.jpg)"
    simplified = web_save_parser.simplify_linked_images(markdown)
    assert simplified.strip() == "![](https://example.com/img.jpg)"


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
    assert parsed.content.count("substack-post-media.s3.amazonaws.com/public/images/hero.webp") == 1


def test_dedupe_markdown_images_handles_linked_title():
    markdown = (
        "![Hero](https://example.com/hero.png)\n\n"
        "[![](https://example.com/hero.png \"Title\")](https://example.com/hero.png)\n"
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
            "![](https://example.com/two.png \"Gallery caption\")",
        ]
    )
    wrapped = web_save_parser.wrap_gallery_blocks(markdown)
    assert "<figure" in wrapped
    assert "image-gallery" in wrapped
    assert "data-caption=\"Gallery caption\"" in wrapped
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
    monkeypatch.setattr(web_save_parser, "Document", FakeDocument)

    parsed = web_save_parser.parse_url_local("example.com/article")
    assert "Content body" in parsed.content


def test_wrap_gallery_blocks_ignores_single_captioned_image():
    markdown = '![](https://example.com/one.png \"Caption\")'
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
    monkeypatch.setattr(web_save_parser, "Document", DummyDocument)

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
    monkeypatch.setattr(web_save_parser, "Document", DummyDocument)

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
