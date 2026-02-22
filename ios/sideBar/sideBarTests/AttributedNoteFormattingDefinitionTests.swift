import XCTest
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
        MarkdownFormattingDefinition().constrainDocument(&constrained)

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
        MarkdownFormattingDefinition().constrainDocument(&constrained)

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
        MarkdownFormattingDefinition().constrainDocument(&constrained)

        XCTAssertNil(constrained[range].runs.first?.inlineMarker)
        XCTAssertNil(constrained[range].runs.first?.listMarker)
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
}
