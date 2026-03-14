import textwrap

from api.services.web_save_antibot import detect_antibot_html, is_antibot_html


def test_detects_cloudflare_challenge():
    html = textwrap.dedent(
        """
        <html>
          <head><title>Just a moment...</title></head>
          <body>
            <div class="cf-browser-verification">Checking your browser before accessing</div>
            <div id="challenge-form">Please enable cookies before proceeding.</div>
          </body>
        </html>
        """
    )

    detection = detect_antibot_html(html)

    assert detection is not None
    assert detection.challenge_kind == "cloudflare"
    assert "Just a moment" in detection.reason


def test_returns_none_for_regular_article():
    html = textwrap.dedent(
        """
        <html>
          <head><title>News story</title></head>
          <body>
            <article>A normal article body without challenges.</article>
          </body>
        </html>
        """
    )

    assert is_antibot_html(html) is False
    assert detect_antibot_html(html) is None
