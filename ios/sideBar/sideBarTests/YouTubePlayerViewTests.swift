import XCTest
import WebKit
@testable import sideBar

final class YouTubePlayerViewTests: XCTestCase {
    func testPrepareForTeardownClearsDelegates() {
        let webView = WKWebView(frame: .zero)
        let delegate = DummyDelegate()
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

        YouTubePlayerWebViewLifecycle.prepareForTeardown(webView)

        XCTAssertNil(webView.navigationDelegate)
        XCTAssertNil(webView.uiDelegate)
    }

    func testTeardownJavaScriptBlanksEmbeddedMediaSources() {
        XCTAssertTrue(YouTubePlayerWebViewLifecycle.teardownJavaScript.contains("iframe"))
        XCTAssertTrue(YouTubePlayerWebViewLifecycle.teardownJavaScript.contains("about:blank"))
        XCTAssertTrue(YouTubePlayerWebViewLifecycle.teardownJavaScript.contains("pause"))
    }
}

private final class DummyDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
}
