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
    func testConstrainDocumentPreservesFoundationPresentationIntentWhileRemovingListDelimiter() throws {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        let intent = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: PresentationIntent(.unorderedList, identity: 2)
        )
        content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = intent
        content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"
        content[range].strikethroughStyle = .single
        content[range].underlineStyle = .single

        NoteTextFormattingDefinition(baseFontSize: 18).constrainDocument(&content)

        XCTAssertEqual(
            try XCTUnwrap(content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]),
            intent
        )
        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self])
        XCTAssertEqual(content[range].strikethroughStyle, .single)
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
                    .init(type: .title, content: [.init(text: "hello", marks: [.bold, .italic])])
                ]
            )
        )
    }

    func testConstrainDocumentDoesNotPromoteBridgedPlatformFontTraitsWithoutSwiftUIFont() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
#if os(iOS)
        let font = UIFont.boldSystemFont(ofSize: 14)
#elseif os(macOS)
        let font = NSFont.systemFont(ofSize: 14, weight: .bold)
#endif
        applyBridgedPlatformFont(
            font,
            to: &content,
            range: range
        )
        content[range].font = nil
        content[range].noteBlock = NotesSemanticDocument.BlockType.paragraph.rawValue

        NoteTextFormattingDefinition(baseFontSize: 20).constrainDocument(&content)

        XCTAssertFalse(noteRangeHasBoldTrait(content, range: range))
        XCTAssertEqual(
            NotesAttributedDocumentCodec.document(from: content),
            NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "hello", marks: [])])
                ]
            )
        )
    }

    func testConstrainDocumentPreservesAppOwnedBlockMarkerAndPlatformListIntent() throws {
        var content = AttributedString("- item")
        let range = content.startIndex..<content.endIndex
        content[range].noteBlock = NoteTextBlockAttribute.unorderedListRawValue
        let intent = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: PresentationIntent(.unorderedList, identity: 2)
        )
        content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = intent
        content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "-"

        NoteTextFormattingDefinition(baseFontSize: 18).constrainDocument(&content)

        XCTAssertEqual(content[range].noteBlock, NoteTextBlockAttribute.unorderedListRawValue)
        XCTAssertEqual(
            try XCTUnwrap(content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]),
            intent
        )
        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self])
        XCTAssertEqual(
            NotesAttributedDocumentCodec.document(from: content),
            NotesSemanticDocument(
                blocks: [
                    .init(
                        type: .unorderedList,
                        children: [
                            .init(type: .listItem, content: [.init(text: "item", marks: [])])
                        ]
                    )
                ]
            )
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func applyBridgedPlatformFont(
    _ font: NotePlatformFont,
    to attributed: inout AttributedString,
    range: Range<AttributedString.Index>
) {
    let plainText = String(attributed.characters)
    let lowerCharacterOffset = attributed.characters.distance(from: attributed.startIndex, to: range.lowerBound)
    let upperCharacterOffset = attributed.characters.distance(from: attributed.startIndex, to: range.upperBound)
    let lower = plainText.index(plainText.startIndex, offsetBy: lowerCharacterOffset)
    let upper = plainText.index(plainText.startIndex, offsetBy: upperCharacterOffset)
    let nsRange = NSRange(
        location: lower.utf16Offset(in: plainText),
        length: upper.utf16Offset(in: plainText) - lower.utf16Offset(in: plainText)
    )
    let bridged = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
    bridged.addAttribute(.font, value: font, range: nsRange)
    guard let bridgedAttributed = try? AttributedString(bridged, including: \.noteTextEditor) else {
        XCTFail("Expected bridged attributed string to remain convertible")
        return
    }
    attributed = bridgedAttributed
}
