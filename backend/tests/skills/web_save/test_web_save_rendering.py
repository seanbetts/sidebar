import os

from api.services import web_save_rendering


def test_requires_js_rendering_for_unrendered_youtube_embed():
    html = "<div>https://www.youtube.com/embed/abc123</div>"
    assert web_save_rendering.requires_js_rendering(html) is True


def test_requires_js_rendering_false_for_regular_html():
    html = "<html><body>" + ("<p>hello world</p>" * 50) + "</body></html>"
    assert web_save_rendering.requires_js_rendering(html) is False


def test_has_unrendered_youtube_embed_detects_missing_iframe():
    html = "<div>https://www.youtube.com/embed/abc123</div>"
    assert web_save_rendering.has_unrendered_youtube_embed(html) is True


def test_has_unrendered_youtube_embed_false_when_iframe_present():
    html = '<iframe src="https://www.youtube.com/embed/abc123"></iframe>'
    assert web_save_rendering.has_unrendered_youtube_embed(html) is False


def test_configure_playwright_browsers_path_prefers_shared_install(monkeypatch, tmp_path):
    shared_path = tmp_path / "ms-playwright"
    shared_path.mkdir()

    monkeypatch.delenv("PLAYWRIGHT_BROWSERS_PATH", raising=False)

    resolved = web_save_rendering.configure_playwright_browsers_path(
        default_path=shared_path
    )

    assert resolved == str(shared_path)
    assert os.environ["PLAYWRIGHT_BROWSERS_PATH"] == str(shared_path)


def test_configure_playwright_browsers_path_preserves_existing_env(monkeypatch, tmp_path):
    shared_path = tmp_path / "ms-playwright"
    shared_path.mkdir()

    monkeypatch.setenv("PLAYWRIGHT_BROWSERS_PATH", "/custom/playwright")

    resolved = web_save_rendering.configure_playwright_browsers_path(
        default_path=shared_path
    )

    assert resolved == "/custom/playwright"
    assert os.environ["PLAYWRIGHT_BROWSERS_PATH"] == "/custom/playwright"
