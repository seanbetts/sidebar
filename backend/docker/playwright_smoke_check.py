"""Fail-fast startup check for Playwright Chromium availability."""

from playwright.sync_api import sync_playwright


def main() -> None:
    """Launch Chromium and load a blank page."""
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("about:blank")
        browser.close()


if __name__ == "__main__":
    main()
