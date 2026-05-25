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

    func testPopupExternalOpensRouteThroughFilteredURLPolicy() throws {
        let youTubeSource = try normalizedSource(at: ["sideBar", "Views", "Files", "YouTubePlayerView.swift"])
        let tikTokSource = try normalizedSource(at: ["sideBar", "Views", "Files", "TikTokEmbedView.swift"])

        XCTAssertFalse(youTubeSource.contains("ifleturl=navigationAction.request.url{openExternally(url)}"))
        XCTAssertFalse(tikTokSource.contains("ifleturl=navigationAction.request.url{openExternally(url)}"))
        XCTAssertEqual(
            youTubeSource.occurrenceCount(of: "ifletexternalURL=externalURL(for:navigationAction){openExternally(externalURL)"),
            4
        )
        XCTAssertEqual(
            tikTokSource.occurrenceCount(of: "ifletexternalURL=externalURL(for:navigationAction){openExternally(externalURL)"),
            2
        )
    }

    func testExternalEmbedOpensRequireHTTPS() throws {
        let youTubeSource = try normalizedSource(at: ["sideBar", "Views", "Files", "YouTubePlayerView.swift"])
        let tikTokSource = try normalizedSource(at: ["sideBar", "Views", "Files", "TikTokEmbedView.swift"])

        XCTAssertEqual(youTubeSource.occurrenceCount(of: "url.scheme?.lowercased()==\"https\""), 2)
        XCTAssertEqual(tikTokSource.occurrenceCount(of: "url.scheme?.lowercased()==\"https\""), 1)
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class DummyDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
