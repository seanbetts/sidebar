import XCTest
@testable import sideBar

@MainActor
final class AttributedNoteTextSurfaceBridgeTests: XCTestCase {
    @available(iOS 26.0, macOS 26.0, *)
    func testScopedBridgePreservesNoteTextEditorAttributes() throws {
        var text = AttributedString("- [ ] Item")
        let range = text.startIndex..<text.endIndex

        text[range].blockKind = .taskUnchecked
        text[range].listDepth = 2
        text[range].listMarker = true
        text[range].inlineMarker = true

        let bridged = try NSAttributedString(text, including: \.testAttributedNoteBridge)
        let roundTripped = try AttributedString(bridged, including: \.testAttributedNoteBridge)
        let outputRange = roundTripped.startIndex..<roundTripped.endIndex

        XCTAssertEqual(roundTripped[outputRange].blockKind, .taskUnchecked)
        XCTAssertEqual(roundTripped[outputRange].listDepth, 2)
        XCTAssertEqual(roundTripped[outputRange].listMarker, true)
        XCTAssertEqual(roundTripped[outputRange].inlineMarker, true)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private extension AttributeScopes {
    struct TestAttributedNoteBridgeAttributes: AttributeScope {
        let noteTextEditor: NoteTextEditorAttributes
        #if os(iOS)
        let uiKit: UIKitAttributes
        #elseif os(macOS)
        let appKit: AppKitAttributes
        #endif
    }

    var testAttributedNoteBridge: TestAttributedNoteBridgeAttributes.Type {
        TestAttributedNoteBridgeAttributes.self
    }
}
