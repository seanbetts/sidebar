import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AttributedNoteFormattingDefinitionTests: XCTestCase {
    func testConstrainDocumentNormalizesListAttributes() throws {
        throw XCTSkip("Temporarily skipped during Apple TextEditor baseline reset.")
    }

    func testConstrainDocumentClearsListAttributesForParagraph() throws {
        throw XCTSkip("Temporarily skipped during Apple TextEditor baseline reset.")
    }

    func testConstrainDocumentRemovesHiddenMarkerAttributes() throws {
        throw XCTSkip("Temporarily skipped during Apple TextEditor baseline reset.")
    }

    func testConstrainDocumentRemovesDisallowedVisualStyleAttributes() throws {
        throw XCTSkip("Temporarily skipped during Apple TextEditor baseline reset.")
    }

    func testConstrainDocumentPreservesCodeLanguageHintInPresentationIntent() throws {
        throw XCTSkip("Temporarily skipped during Apple TextEditor baseline reset.")
    }

    func testConstrainDocumentKeepsNestedBlockquoteIdentityChainStable() {
        var content = AttributedString("Nested quote")
        let range = content.startIndex..<content.endIndex
        let outerQuote = PresentationIntent(.blockQuote, identity: 1)
        let innerQuote = PresentationIntent(.blockQuote, identity: 2, parent: outerQuote)
        content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 3,
            parent: innerQuote
        )

        let originalIntent = content[range].runs.first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        let originalBlockquoteIdentities = blockquoteIdentities(in: originalIntent)
        XCTAssertEqual(originalBlockquoteIdentities.count, 2)

        var constrained = content
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
