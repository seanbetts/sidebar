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
final class NativeMarkdownListMarkerTests: XCTestCase {
    func testUpdatePrefixVisibilityRestylesExistingReadMarkerFont() async {
        let viewModel = NativeMarkdownEditorViewModel()
        var content = AttributedString("• Item")
        let markerEnd = content.index(content.startIndex, offsetByCharacters: 2)
        let markerRange = content.startIndex..<markerEnd
        let textRange = markerEnd..<content.endIndex
        content[markerRange].listMarker = true
        content[markerRange].blockKind = .bulletList
        content[markerRange].listDepth = 1
        content[textRange].blockKind = .bulletList
        content[textRange].listDepth = 1
#if os(iOS)
        content[markerRange][AttributeScopes.UIKitAttributes.FontAttribute.self] = UIFont.systemFont(ofSize: 8)
#elseif os(macOS)
        content[markerRange][AttributeScopes.AppKitAttributes.FontAttribute.self] = NSFont.systemFont(ofSize: 8)
#endif

        viewModel.attributedContent = content
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.updatePrefixVisibility()

        guard let markerRun = viewModel.attributedContent.runs.first(where: { $0.listMarker == true }) else {
            XCTFail("Expected a styled marker run")
            return
        }
#if os(iOS)
        let markerFont = markerRun[AttributeScopes.UIKitAttributes.FontAttribute.self]
#elseif os(macOS)
        let markerFont = markerRun[AttributeScopes.AppKitAttributes.FontAttribute.self]
#endif
        XCTAssertEqual(markerFont?.pointSize ?? 0, viewModel.baseFontSize, accuracy: 0.1)
    }
}
