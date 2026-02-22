import XCTest
@testable import sideBar

final class NotesDetailViewTests: XCTestCase {
    func testResolveEditorRenderingModeFallsBackToLegacyWhenNativeUnavailable() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: false,
            useAttributedNoteEditorV2: true
        )

        XCTAssertEqual(mode, .markdownLegacy)
    }

    func testResolveEditorRenderingModeUsesV2WhenEnabled() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: true,
            useAttributedNoteEditorV2: true
        )

        XCTAssertEqual(mode, .attributedV2)
    }

    func testResolveEditorRenderingModeUsesLegacyWhenV2Disabled() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: true,
            useAttributedNoteEditorV2: false
        )

        XCTAssertEqual(mode, .markdownLegacy)
    }

    func testResolveEditorRenderingModeUsesLegacyWhenNativeUnavailableAndV2Disabled() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: false,
            useAttributedNoteEditorV2: false
        )

        XCTAssertEqual(mode, .markdownLegacy)
    }
}
