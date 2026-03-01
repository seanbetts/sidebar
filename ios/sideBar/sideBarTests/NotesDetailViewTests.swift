import XCTest
@testable import sideBar

final class NotesDetailViewTests: XCTestCase {
    func testResolveEditorRenderingModeFallsBackToUnavailableWhenNativeUnsupported() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: false
        )

        XCTAssertEqual(mode, .unavailable)
    }

    func testResolveEditorRenderingModeUsesAttributedWhenNativeSupported() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: true
        )

        XCTAssertEqual(mode, .attributed)
    }
}
