@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func normalizeTypingAfterBlockquoteNewlineIfNeeded(insertedCharacter: Character?) {
        guard insertedCharacter == "\n" else { return }
        guard let insertionIndex = insertionIndexAfterEdit(in: attributedContent),
              insertionIndex > attributedContent.startIndex else {
            return
        }

        let previousIndex = attributedContent.index(beforeCharacter: insertionIndex)
        let previousParagraph = findParagraphRange(containing: previousIndex..<previousIndex)
        guard !previousParagraph.isEmpty else { return }

        let previousBlockKind = attributedContent[previousParagraph].blockKind
            ?? attributedContent.blockKind(in: previousParagraph)
            ?? inferredBlockKind(from: String(attributedContent[previousParagraph].characters))
        guard previousBlockKind == .blockquote else { return }

        let currentParagraph = findParagraphRange(containing: insertionIndex..<insertionIndex)
        if !currentParagraph.isEmpty {
            let currentText = String(attributedContent[currentParagraph].characters)
            guard currentText.isEmpty else { return }
        }

        transformSelectionAttributes { attrs in
            attrs.blockKind = .paragraph
            attrs.listDepth = nil
            attrs.codeLanguage = nil
            setFont(
                baseFont(for: .paragraph),
                platformFont: platformBaseFont(for: .paragraph),
                in: &attrs
            )
            setForegroundColor(baseForegroundColor(for: .paragraph), in: &attrs)
            setBackgroundColor(baseBackgroundColor(for: .paragraph), in: &attrs)
            attrs.paragraphStyle = paragraphStyle(for: .paragraph, listDepth: nil)
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = typingPresentationIntent(
                blockKind: .paragraph,
                listDepth: nil
            )
            attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
            attrs.strikethroughStyle = nil
        }
    }

    private func insertionIndexAfterEdit(in text: AttributedString) -> AttributedString.Index? {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return index
        case .ranges(let ranges):
            for range in ranges.ranges where range.isEmpty {
                return range.lowerBound
            }
            return nil
        }
    }
}
