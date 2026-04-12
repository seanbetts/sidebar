import XCTest
@testable import sideBar

#if os(macOS)
import AppKit

@MainActor
final class SystemSharePresenterLogicTests: XCTestCase {
    override func tearDown() {
        SystemShareAnchorRegistry.resetForTesting()
        super.tearDown()
    }

    func testMacOSPresentationTargetUsesRegisteredAnchorViewBounds() throws {
        let window = makeWindow(size: NSSize(width: 640, height: 480))
        let anchorView = NSView(frame: NSRect(x: 48, y: 96, width: 120, height: 32))
        window.contentView?.addSubview(anchorView)

        SystemShareAnchorRegistry.register(anchorView, for: "website-row")

        let target = try XCTUnwrap(
            SystemSharePresenter.macOSPresentationTarget(
                anchorID: "website-row",
                fallbackWindow: window
            )
        )

        XCTAssertTrue(target.sourceView === anchorView)
        XCTAssertEqual(target.sourceRect, anchorView.bounds)
    }

    func testMacOSPresentationTargetFallsBackToCenteredWindowContentView() throws {
        let window = makeWindow(size: NSSize(width: 500, height: 300))

        let target = try XCTUnwrap(
            SystemSharePresenter.macOSPresentationTarget(
                anchorID: "missing-anchor",
                fallbackWindow: window
            )
        )

        let expectedView = try XCTUnwrap(window.contentView)
        XCTAssertTrue(target.sourceView === expectedView)
        XCTAssertEqual(target.sourceRect, NSRect(x: 250, y: 150, width: 1, height: 1))
    }

    private func makeWindow(size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: NSRect(origin: .zero, size: size))
        return window
    }
}
#endif
