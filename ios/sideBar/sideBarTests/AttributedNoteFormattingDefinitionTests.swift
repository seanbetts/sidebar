import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AttributedNoteFormattingDefinitionTests: XCTestCase {
    func testConstrainDocumentRemovesUnsupportedBlockMetadata() {
        var content = AttributedString("List item")
        let range = content.startIndex..<content.endIndex
        content[range].blockKind = .bulletList
        content[range].listDepth = 2
        content[range].codeLanguage = "swift"
        content[range].inlineMarker = true
        content[range].listMarker = true
        content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: PresentationIntent(.unorderedList, identity: 2)
        )
        content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"

        NoteTextFormattingDefinition().constrainDocument(&content)

        XCTAssertNil(content[range].blockKind)
        XCTAssertNil(content[range].listDepth)
        XCTAssertNil(content[range].codeLanguage)
        XCTAssertNil(content[range].inlineMarker)
        XCTAssertNil(content[range].listMarker)
        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self])
        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self])
    }

    func testConstrainDocumentRemovesUnsupportedInlineCodeAndStrikethrough() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        content[range].inlinePresentationIntent = [.code, .stronglyEmphasized]
        content[range].strikethroughStyle = .single
        content[range].underlineStyle = .single

        NoteTextFormattingDefinition().constrainDocument(&content)

        XCTAssertEqual(content[range].inlinePresentationIntent, [.stronglyEmphasized])
        XCTAssertNil(content[range].strikethroughStyle)
        XCTAssertEqual(content[range].underlineStyle, .single)
    }

    func testConstrainDocumentNormalizesSupportedInlineFonts() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        content[range].font = .system(size: 18, weight: .bold).italic()

        NoteTextFormattingDefinition().constrainDocument(&content)

        let resolved = content[range].font?.resolve(in: EnvironmentValues().fontResolutionContext)
        XCTAssertEqual(resolved?.isBold, true)
        XCTAssertEqual(resolved?.isItalic, true)
    }
}
