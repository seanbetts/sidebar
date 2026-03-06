import XCTest
import SwiftUI
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

    func testConstrainDocumentNormalizesSupportedInlineFonts() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        content[range].font = .system(size: 14, weight: .bold).italic()

        NoteTextFormattingDefinition(baseFontSize: 24).constrainDocument(&content)

        let resolved = content[range].font?.resolve(in: EnvironmentValues().fontResolutionContext)
        XCTAssertEqual(resolved?.isBold, true)
        XCTAssertEqual(resolved?.isItalic, true)
        let exported = NotesRichTextCodec.encodeAttributedStringToBase64RTF(
            content,
            baseFontSize: 24
        )
        XCTAssertEqual(noteFirstRunPointSize(inCanonicalRTF: exported ?? "") ?? 0, 24, accuracy: 1.0)
    }
}
