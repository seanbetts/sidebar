@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    public func applyCodeBlock(language: String?) {
        guard !isReadOnly else { return }
        let previousContent = attributedContent
        let previousSelection = selection
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguage = (trimmedLanguage?.isEmpty == false) ? trimmedLanguage : nil
        let paragraphRanges = selectedParagraphRanges()
        setBlockKind(.codeBlock)
        if !paragraphRanges.isEmpty {
            for paragraphRange in paragraphRanges {
                attributedContent[paragraphRange].codeLanguage = normalizedLanguage
                applyPresentationIntent(
                    blockKind: .codeBlock,
                    listDepth: nil,
                    range: paragraphRange
                )
            }
        } else {
            transformSelectionAttributes { attrs in
                attrs.codeLanguage = normalizedLanguage
                attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                    .codeBlock(languageHint: normalizedLanguage),
                    identity: 1
                )
            }
        }

        guard attributedContent != previousContent || selection != previousSelection else { return }
        hasUnsavedChanges = true
        scheduleAutosave()
        let selectionSpan = selectionLineSpan(in: attributedContent)
        lastSelectionLineSpan = selectionSpan
        refreshPrefixVisibility(scope: .full)
    }
}
