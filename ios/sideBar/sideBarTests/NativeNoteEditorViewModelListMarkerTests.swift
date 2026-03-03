import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteListMarkerTests: XCTestCase {
    func testUpdatePrefixVisibilityRestylesExistingReadMarkerFont() async {
        let viewModel = NativeNoteEditorViewModel()
        var content = AttributedString("• Item")
        let markerEnd = content.index(content.startIndex, offsetByCharacters: 2)
        let markerRange = content.startIndex..<markerEnd
        let textRange = markerEnd..<content.endIndex
        content[markerRange].listMarker = true
        content[markerRange].blockKind = .bulletList
        content[markerRange].listDepth = 1
        content[textRange].blockKind = .bulletList
        content[textRange].listDepth = 1
        content[markerRange].font = .system(size: 8)

        viewModel.attributedContent = content
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.updatePrefixVisibility()

        guard let markerRun = viewModel.attributedContent.runs.first(where: { $0.listMarker == true }) else {
            XCTFail("Expected a styled marker run")
            return
        }
#if os(iOS)
        let bridged = NSAttributedString(AttributedString(viewModel.attributedContent[markerRun.range]))
        let markerFont = bridged.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(markerFont?.pointSize ?? 0, viewModel.baseFontSize, accuracy: 0.1)
#elseif os(macOS)
        XCTAssertNotNil(markerRun.font)
#endif
    }
}
