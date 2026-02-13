"""Tests for hbr.org-specific parsing behavior."""

from __future__ import annotations

import json

from api.services import web_save_parser
from api.services.web_save_parser_hbr import extract_hbr_body_html


def _build_hbr_html(*, include_structured_data: bool = True) -> str:
    article_body = (
        "Visibility matters at every level. "
        "Speak to Scale Describe the scope of your remit with concrete numbers. "
        "Show Strategic Judgement Explain why you made key tradeoffs. "
        "Highlight your Stewardship Connect outcomes to team growth."
    )
    structured_data = {
        "@context": "https://schema.org",
        "@type": "Article",
        "headline": "How Leaders Communicate Wins",
        "datePublished": "2026-02-01T12:00:00Z",
        "url": "https://hbr.org/2026/02/how-leaders-communicate-wins",
        "author": [{"@type": "Person", "name": "Alex Example"}],
        "articleBody": article_body,
    }
    structured_data_tag = ""
    if include_structured_data:
        structured_data_tag = (
            '<script id="structured-data" type="application/ld+json">'
            f"{json.dumps(structured_data)}</script>"
        )
    return f"""
    <html>
      <head>
        <title>How Leaders Communicate Wins</title>
        <link rel="canonical" href="https://hbr.org/2026/02/how-leaders-communicate-wins"/>
        <meta property="article:published_time" content="2026-02-01T12:00:00Z"/>
        {structured_data_tag}
      </head>
      <body>
        <article id="main" class="ArticleWrapper_wrapper__yWBsB">
          <div class="Standard_content__mghDk">
            <p>Preview teaser only.</p>
          </div>
          <div class="RelatedTopics_container__2Nkb4">Read more on strategy</div>
        </article>
      </body>
    </html>
    """


def test_extract_hbr_body_html_from_structured_data():
    payload = extract_hbr_body_html(_build_hbr_html())
    assert payload is not None
    article_html, metadata = payload
    assert "<h2>Speak to Scale</h2>" in article_html
    assert "<h2>Show Strategic Judgement</h2>" in article_html
    assert "Describe the scope of your remit with concrete numbers." in article_html
    assert "Preview teaser only." not in article_html
    assert metadata["author"] == "Alex Example"
    assert metadata["published"] == "2026-02-01T12:00:00Z"


def test_hbr_rules_remove_related_topics_and_match_host():
    html = """
    <html>
      <body>
        <article id="main">
          <div class="Standard_content__mghDk"><p>Main text.</p></div>
          <div class="RelatedTopics_container__2Nkb4">Read more on strategy</div>
        </article>
      </body>
    </html>
    """
    engine = web_save_parser.RuleEngine.from_rules_dir(web_save_parser.RULES_DIR)
    matched = engine.match_rules("https://hbr.org/example", html, phase="post")
    matched_ids = {rule.id for rule in matched}
    assert "hbr-cleanup" in matched_ids
    cleaned = engine.apply_rules(html, matched)
    assert "Read more on strategy" not in cleaned
    assert "Main text." in cleaned


def test_parse_url_local_hbr_prefers_structured_data_body(monkeypatch):
    html = _build_hbr_html()

    def fake_fetch(url: str, *, timeout: int = 30):
        return html, "https://hbr.org/2026/02/how-leaders-communicate-wins", False

    monkeypatch.setattr(web_save_parser, "fetch_html", fake_fetch)
    monkeypatch.setattr(
        web_save_parser, "_favicon_exists", lambda url, timeout=8: False
    )
    monkeypatch.setattr(
        web_save_parser, "get_rule_engine", lambda: web_save_parser.RuleEngine([])
    )

    parsed = web_save_parser.parse_url_local(
        "https://hbr.org/2026/02/how-leaders-communicate-wins"
    )

    frontmatter = parsed.content.split("---\n", 2)[1]
    data = web_save_parser.yaml.safe_load(frontmatter)
    assert parsed.title == "How Leaders Communicate Wins"
    assert parsed.source == "https://hbr.org/2026/02/how-leaders-communicate-wins"
    assert data["author"] == "Alex Example"
    assert data["published_date"] == "2026-02-01T12:00:00+00:00"
    assert "Preview teaser only." not in parsed.content
    assert "Describe the scope of your remit with concrete numbers." in parsed.content
