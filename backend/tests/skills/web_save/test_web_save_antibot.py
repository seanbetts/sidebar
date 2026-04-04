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
    assert "Checking your browser before accessing" in detection.reason


def test_cloudflare_title_only_not_detected():
    html = textwrap.dedent(
        """
        <html>
          <head><title>Just a moment...</title></head>
          <body>
            <p>Redirecting…</p>
          </body>
        </html>
        """
    )

    assert detect_antibot_html(html) is None


def test_detects_generic_challenge_marker():
    html = textwrap.dedent(
        """
        <html>
          <head><title>Access blocked</title></head>
          <body>
            <div class="challenge-form">Please complete the form</div>
          </body>
        </html>
        """
    )

    detection = detect_antibot_html(html)

    assert detection is not None
    assert detection.challenge_kind == "generic"
    assert "challenge-form" in detection.reason


def test_detects_datadome_challenge_marker():
    html = textwrap.dedent(
        """
        <html>
          <head><title>reuters.com</title></head>
          <body>
            <iframe src="https://geo.captcha-delivery.com/captcha/" title="DataDome CAPTCHA"></iframe>
            <p>Please enable JS and disable any ad blocker</p>
          </body>
        </html>
        """
    )

    detection = detect_antibot_html(html)

    assert detection is not None
    assert detection.challenge_kind == "generic"
    assert "DataDome" in detection.reason or "enable js and disable any ad blocker" in detection.reason.lower()


def test_detects_google_unusual_traffic_page_in_markdown_text():
    html = textwrap.dedent(
        """
        Our systems have detected unusual traffic from your computer network.

        This page checks to see if it's really you sending the requests, and not a robot.

        In the meantime, solving the above CAPTCHA will let you continue to use our services.
        """
    )

    detection = detect_antibot_html(html)

    assert detection is not None
    assert detection.challenge_kind == "google"
    assert "unusual traffic" in detection.reason.lower()
    assert "captcha" in detection.reason.lower() or "robot" in detection.reason.lower()


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
