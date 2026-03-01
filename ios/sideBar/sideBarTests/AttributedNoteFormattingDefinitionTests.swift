import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AttributedNoteFormattingDefinitionTests: XCTestCase {
    func testConstrainDocumentNormalizesListAttributes() {
        var text = AttributedString("Item")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .bulletList
        text[range].listDepth = 0
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "-"

        var constrained = text
        NoteTextFormattingDefinition().constrainDocument(&constrained)

        XCTAssertEqual(constrained[range].listDepth, 1)
        XCTAssertEqual(
            constrained[range].runs.first?[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self],
            "•"
        )
        let intent = constrained[range].runs.first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        XCTAssertTrue(containsUnorderedList(in: intent))
        XCTAssertTrue(containsListItem(in: intent))
    }

    func testConstrainDocumentClearsListAttributesForParagraph() {
        var text = AttributedString("Paragraph")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .paragraph
        text[range].listDepth = 4
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"
        text[range].codeLanguage = "swift"

        var constrained = text
        NoteTextFormattingDefinition().constrainDocument(&constrained)

        XCTAssertNil(constrained[range].listDepth)
        XCTAssertNil(constrained[range].runs.first?[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self])
        XCTAssertNil(constrained[range].codeLanguage)
    }

    func testConstrainDocumentRemovesHiddenMarkerAttributes() {
        var text = AttributedString("Visible content")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .paragraph
        text[range].inlineMarker = true
        text[range].listMarker = true

        var constrained = text
        NoteTextFormattingDefinition().constrainDocument(&constrained)

        XCTAssertNil(constrained[range].runs.first?.inlineMarker)
        XCTAssertNil(constrained[range].runs.first?.listMarker)
    }

    func testConstrainDocumentRemovesDisallowedVisualStyleAttributes() {
        var text = AttributedString("Styled paragraph")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .paragraph
        text[range].font = .system(size: 42, weight: .black)
        text[range].foregroundColor = .red
        text[range].backgroundColor = .yellow
        text[range].paragraphStyle = {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = 99
            style.firstLineHeadIndent = 27
            return style
        }()
        text[range].strikethroughStyle = .single

        var constrained = text
        NoteTextFormattingDefinition().constrainDocument(&constrained)

        XCTAssertNil(constrained[range].font)
        XCTAssertNil(constrained[range].foregroundColor)
        XCTAssertNil(constrained[range].backgroundColor)
        XCTAssertNil(constrained[range].paragraphStyle)
        XCTAssertEqual(constrained[range].strikethroughStyle, .single)
    }

    func testConstrainDocumentPreservesCodeLanguageHintInPresentationIntent() {
        var text = AttributedString("print(\"hello\")")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .codeBlock
        text[range].codeLanguage = "swift"

        var constrained = text
        NoteTextFormattingDefinition().constrainDocument(&constrained)

        let intent = constrained[range].runs.first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        XCTAssertEqual(codeBlockLanguageHint(in: intent), "swift")
    }

    func testConstrainDocumentKeepsNestedBlockquoteIdentityChainStable() {
        let markdown = """
        > > Nested quote
        """
        let imported = NoteTextImporter().attributedString(from: markdown).attributedString
        let range = imported.startIndex..<imported.endIndex
        let originalIntent = imported[range].runs.first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        let originalBlockquoteIdentities = blockquoteIdentities(in: originalIntent)
        XCTAssertEqual(originalBlockquoteIdentities.count, 2)

        var constrained = imported
        NoteTextFormattingDefinition().constrainDocument(&constrained)

        let constrainedIntent = constrained[range].runs.first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        XCTAssertEqual(blockquoteIdentities(in: constrainedIntent), originalBlockquoteIdentities)
    }

    private func containsUnorderedList(in intent: PresentationIntent?) -> Bool {
        guard let intent else { return false }
        for component in intent.components {
            if case .unorderedList = component.kind {
                return true
            }
        }
        return false
    }

    private func containsListItem(in intent: PresentationIntent?) -> Bool {
        guard let intent else { return false }
        for component in intent.components {
            if case .listItem = component.kind {
                return true
            }
        }
        return false
    }

    private func codeBlockLanguageHint(in intent: PresentationIntent?) -> String? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .codeBlock(let languageHint) = component.kind {
                return languageHint
            }
        }
        return nil
    }

    private func blockquoteIdentities(in intent: PresentationIntent?) -> [Int] {
        guard let intent else { return [] }
        return intent.components.compactMap { component in
            if case .blockQuote = component.kind {
                return component.identity
            }
            return nil
        }
    }
}
