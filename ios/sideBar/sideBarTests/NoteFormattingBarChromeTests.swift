import XCTest
@testable import sideBar

@MainActor
final class NoteFormattingBarChromeTests: XCTestCase {
    func testSharedFormattingBarChromeUsesActionButtonKind() {
        XCTAssertEqual(NoteFormattingBarChrome.entryControlKind, .actionButton)
    }

    func testSharedFormattingBarChromeUsesSharedActionButtonCornerRadius() {
        XCTAssertEqual(NoteFormattingBarChrome.cornerRadius(for: 44), DesignTokens.Radius.sm, accuracy: 0.01)
        XCTAssertEqual(NoteFormattingBarChrome.cornerRadius(for: 52), DesignTokens.Radius.sm, accuracy: 0.01)
    }

    func testFormattingBarSourcesUseSharedChromeHelper() throws {
        let swiftUIViewSource = try source(
            at: "Views/Notes/NoteFormattingBar.swift"
        )
        let detailFormattingBarSource = try source(
            at: "Views/Notes/NotesDetailView+FormattingBar.swift"
        )
        let uiKitSource = try source(
            at: "Views/Notes/UIKitNoteFormattingBar.swift"
        )
        let appKitSource = try source(
            at: "Views/Notes/AppKitNoteFormattingBar.swift"
        )

        XCTAssertTrue(swiftUIViewSource.contains("HeaderActionMenuControl("))
        XCTAssertTrue(swiftUIViewSource.contains("systemName: \"textformat\""))
        XCTAssertTrue(detailFormattingBarSource.contains("formattingBarPresentation == .floatingTopTrailing"))
        XCTAssertTrue(detailFormattingBarSource.contains("NoteFormattingBar(configuration: configuration)"))
        XCTAssertTrue(detailFormattingBarSource.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(detailFormattingBarSource.contains("showsVisibleChrome: false"))
        XCTAssertFalse(detailFormattingBarSource.contains(".opacity("))
        XCTAssertTrue(detailFormattingBarSource.contains("UIKitNoteFormattingBarRepresentable("))
        XCTAssertTrue(detailFormattingBarSource.contains("AppKitNoteFormattingOverlay("))
        XCTAssertTrue(uiKitSource.contains("NoteFormattingBarChrome.cornerRadius(for: Self.barHeight)"))
        XCTAssertTrue(uiKitSource.contains("HeaderActionControlChromeBridge.borderColor("))
        XCTAssertTrue(uiKitSource.contains("showsVisibleChrome"))
        XCTAssertTrue(uiKitSource.contains("NoteFormattingBarChrome.entrySymbolPointSize"))
        XCTAssertTrue(appKitSource.contains("NoteFormattingBarChrome.cornerRadius(for: Self.barHeight)"))
        XCTAssertTrue(appKitSource.contains("HeaderActionControlChromeBridge.borderColor("))
        XCTAssertTrue(appKitSource.contains("showsVisibleChrome"))
        XCTAssertTrue(appKitSource.contains("NoteFormattingBarChrome.entrySymbolPointSize"))
    }

    func testSharedFormattingBarChromeUsesSharedHeaderActionIconPointSize() {
        XCTAssertEqual(
            NoteFormattingBarChrome.entrySymbolPointSize,
            HeaderActionControlMetrics.symbolPointSize
        )
    }

    func testSharedFormattingBarChromeMatchesHeaderActionControlDimensions() {
        XCTAssertEqual(NoteFormattingBarChrome.entryControlWidth, HeaderActionControlMetrics.chromeWidth)
        XCTAssertEqual(NoteFormattingBarChrome.entryControlHeight, HeaderActionControlMetrics.chromeHeight)
    }

    private func source(at relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("sideBar")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
