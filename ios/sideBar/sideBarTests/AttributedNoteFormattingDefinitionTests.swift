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
final class AttributedNoteFormattingDefinitionTests: XCTestCase {
    func testConstrainDocumentRemovesUnsupportedFoundationPresentationAttributes() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: PresentationIntent(.unorderedList, identity: 2)
        )
        content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"
        content[range].strikethroughStyle = .single
        content[range].underlineStyle = .single

        NoteTextFormattingDefinition(baseFontSize: 18).constrainDocument(&content)

        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self])
        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self])
        XCTAssertNil(content[range].strikethroughStyle)
        XCTAssertEqual(content[range].underlineStyle, .single)
    }

    func testConstrainDocumentNormalizesSupportedInlineFonts() throws {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        content[range].font = .system(size: 14, weight: .bold).italic()

        NoteTextFormattingDefinition(baseFontSize: 24).constrainDocument(&content)

        let resolved = content[range].font?.resolve(in: EnvironmentValues().fontResolutionContext)
        XCTAssertEqual(resolved?.isBold, true)
        XCTAssertEqual(resolved?.isItalic, true)
        XCTAssertEqual(
            NotesAttributedDocumentCodec.document(from: content),
            NotesSemanticDocument(
                blocks: [
                    .paragraph([.init(text: "hello", marks: [.bold, .italic])])
                ]
            )
        )
    }

    func testConstrainDocumentDoesNotPromoteBridgedPlatformFontTraitsWithoutSwiftUIFont() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
#if os(iOS)
        content[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = UIFont.boldSystemFont(ofSize: 14)
#elseif os(macOS)
        content[range][AttributeScopes.AppKitAttributes.FontAttribute.self] = NSFont.systemFont(
            ofSize: 14,
            weight: .bold
        )
#endif
        content[range].font = nil

        NoteTextFormattingDefinition(baseFontSize: 20).constrainDocument(&content)

        XCTAssertFalse(noteRangeHasBoldTrait(content, range: range))
    }
}
