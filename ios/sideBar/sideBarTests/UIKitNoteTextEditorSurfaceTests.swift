#if os(iOS)
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteTextEditorSurfaceTests: XCTestCase {
    func testAttributedNoteEditorContainerPrefersUIKitHostOnIOS() {
        XCTAssertEqual(AttributedNoteEditorContainer.preferredEditorSurfaceKind, .uiKit)
    }
}
#endif
