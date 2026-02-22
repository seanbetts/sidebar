import XCTest
@testable import sideBar

final class NotesDetailViewTests: XCTestCase {
    func testResolveEditorRenderingModeFallsBackToLegacyWhenNativeUnavailable() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: false,
            useNativeMarkdownEditor: true,
            useAttributedNoteEditorV2: true
        )

        XCTAssertEqual(mode, .markdownLegacy)
    }

    func testResolveEditorRenderingModeUsesV2WhenEnabled() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: true,
            useNativeMarkdownEditor: true,
            useAttributedNoteEditorV2: true
        )

        XCTAssertEqual(mode, .attributedV2)
    }

    func testResolveEditorRenderingModeUsesNativeV1WhenV2Disabled() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: true,
            useNativeMarkdownEditor: true,
            useAttributedNoteEditorV2: false
        )

        XCTAssertEqual(mode, .nativeMarkdownV1)
    }

    func testResolveEditorRenderingModeUsesLegacyWhenNativeDisabled() {
        let mode = NotesDetailView.resolveEditorRenderingMode(
            osSupportsNative: true,
            useNativeMarkdownEditor: false,
            useAttributedNoteEditorV2: false
        )

        XCTAssertEqual(mode, .markdownLegacy)
    }
}
