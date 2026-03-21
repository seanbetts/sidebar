import os
import sys
from types import ModuleType

from api.services import web_save_rendering
import pytest


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


def test_has_unrendered_substack_native_video_detects_placeholder():
    html = (
        '<div data-component-name="VideoEmbedPlayer" id="media-abc"></div>'
        '<div class="native-video-embed" data-component-name="VideoPlaceholder"></div>'
    )
    assert web_save_rendering.has_unrendered_substack_native_video(html) is True


def test_has_unrendered_substack_native_video_false_when_video_present():
    html = (
        '<div data-component-name="VideoEmbedPlayer" id="media-abc">'
        '<video poster="https://cdn.example.com/poster.png"></video>'
        "</div>"
    )
    assert web_save_rendering.has_unrendered_substack_native_video(html) is False


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


def test_classify_rendered_html_detects_challenge_pages():
    html = (
        "<html><body><div id=\"cf-browser-verification\"></div></body></html>"
    )
    detection = web_save_rendering.classify_rendered_html(
        html, title="Just a moment..."
    )

    assert detection is not None
    assert detection.challenge_kind == "cloudflare"
    assert "cf-browser-verification" in detection.reason


def test_summarize_rendered_page_includes_title_and_classification():
    class FakePage:
        def __init__(self, title: str, html: str) -> None:
            self._title = title
            self._html = html

        def title(self) -> str:
            return self._title

        def content(self) -> str:
            return self._html

    html = (
        "<html><body><div id=\"cf-browser-verification\"></div></body></html>"
    )
    page = FakePage("Just a moment...", html)

    summary = web_save_rendering.summarize_rendered_page(page)

    assert summary.title == "Just a moment..."
    assert summary.html == html
    assert summary.antibot_detection is not None


def test_render_html_with_playwright_aborts_on_antibot_before_wait(monkeypatch):
    ops: list[str] = []
    html = "<html><body><div id=\"cf-browser-verification\"></div></body></html>"
    challenge_url = "https://example.com/challenge"

    class FakePage:
        def goto(self, *args, **kwargs):
            ops.append("goto")

        def wait_for_selector(self, *args, **kwargs):
            ops.append("wait_for")
            raise AssertionError("wait_for_selector should not be called for challenges")

        def content(self) -> str:
            ops.append("content")
            return html

        def title(self) -> str:
            ops.append("title")
            return "Just a moment..."

        @property
        def url(self) -> str:
            ops.append("url")
            return challenge_url

    page = FakePage()

    class FakeContext:
        def __init__(self, page: FakePage) -> None:
            self._page = page

        def new_page(self) -> FakePage:
            ops.append("new_page")
            return self._page

    class FakeBrowser:
        def __init__(self, page: FakePage) -> None:
            self._page = page

        def new_context(self, *, user_agent: str | None = None):
            ops.append("new_context")
            return FakeContext(self._page)

        def close(self) -> None:
            ops.append("browser_close")

    class FakeChromium:
        def __init__(self, page: FakePage) -> None:
            self._page = page

        def launch(self, *args, **kwargs):
            ops.append("launch")
            return FakeBrowser(self._page)

    class FakePlaywright:
        def __init__(self, page: FakePage) -> None:
            self.chromium = FakeChromium(page)

    class FakeSyncPlaywright:
        def __enter__(self) -> FakePlaywright:
            ops.append("playwright_enter")
            return FakePlaywright(page)

        def __exit__(self, exc_type, exc, traceback) -> bool:
            ops.append("playwright_exit")
            return False

    fake_sync_module = ModuleType("playwright.sync_api")
    fake_sync_module.sync_playwright = lambda: FakeSyncPlaywright()
    fake_sync_module.TimeoutError = TimeoutError
    fake_playwright_module = ModuleType("playwright")
    fake_playwright_module.sync_api = fake_sync_module

    monkeypatch.setitem(sys.modules, "playwright", fake_playwright_module)
    monkeypatch.setitem(sys.modules, "playwright.sync_api", fake_sync_module)

    rendered_html, final_url = web_save_rendering.render_html_with_playwright(
        "https://example.com",
        wait_for="#selector",
    )

    assert rendered_html == html
    assert final_url == challenge_url
    assert ops.index("goto") < ops.index("content")
    assert "wait_for" not in ops
    assert "browser_close" in ops


def test_render_html_with_playwright_skips_browser_close_on_navigation_timeout(
    monkeypatch,
):
    ops: list[str] = []

    class FakeTimeoutError(Exception):
        pass

    class FakePage:
        def goto(self, *args, **kwargs):
            ops.append("goto")
            raise FakeTimeoutError("Page.goto: Timeout 15000ms exceeded.")

        def wait_for_selector(self, *args, **kwargs):
            ops.append("wait_for")

        def content(self) -> str:
            ops.append("content")
            return "<html></html>"

        def title(self) -> str:
            ops.append("title")
            return "Timed out"

        @property
        def url(self) -> str:
            ops.append("url")
            return "https://example.com/timeout"

    page = FakePage()

    class FakeContext:
        def __init__(self, page: FakePage) -> None:
            self._page = page

        def new_page(self) -> FakePage:
            ops.append("new_page")
            return self._page

    class FakeBrowser:
        def __init__(self, page: FakePage) -> None:
            self._page = page

        def new_context(self, *, user_agent: str | None = None):
            ops.append("new_context")
            return FakeContext(self._page)

        def close(self) -> None:
            ops.append("browser_close")

    class FakeChromium:
        def __init__(self, page: FakePage) -> None:
            self._page = page

        def launch(self, *args, **kwargs):
            ops.append("launch")
            return FakeBrowser(self._page)

    class FakePlaywright:
        def __init__(self, page: FakePage) -> None:
            self.chromium = FakeChromium(page)

    class FakeSyncPlaywright:
        def __enter__(self) -> FakePlaywright:
            ops.append("playwright_enter")
            return FakePlaywright(page)

        def __exit__(self, exc_type, exc, traceback) -> bool:
            ops.append("playwright_exit")
            return False

    fake_sync_module = ModuleType("playwright.sync_api")
    fake_sync_module.sync_playwright = lambda: FakeSyncPlaywright()
    fake_sync_module.TimeoutError = FakeTimeoutError
    fake_playwright_module = ModuleType("playwright")
    fake_playwright_module.sync_api = fake_sync_module

    monkeypatch.setitem(sys.modules, "playwright", fake_playwright_module)
    monkeypatch.setitem(sys.modules, "playwright.sync_api", fake_sync_module)

    with pytest.raises(FakeTimeoutError):
        web_save_rendering.render_html_with_playwright("https://example.com")

    assert "browser_close" not in ops
    assert "playwright_exit" in ops
