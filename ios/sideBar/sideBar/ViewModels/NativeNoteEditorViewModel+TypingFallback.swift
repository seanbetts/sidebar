@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func contextualTypingFallbackAttributes() -> AttributeContainer {
        if plainTextRuntimeModeEnabled {
            return defaultTypingAttributes()
        }
        guard !attributedContent.characters.isEmpty else {
            return defaultTypingAttributes()
        }
        guard let paragraphRange = selectedParagraphRanges().first, !paragraphRange.isEmpty else {
            return defaultTypingAttributes()
        }

        let blockKind = attributedContent[paragraphRange].blockKind
            ?? attributedContent.blockKind(in: paragraphRange)
            ?? .paragraph
        let listDepth: Int? = isListBlockKind(blockKind)
            ? max(1, attributedContent[paragraphRange].listDepth ?? 1)
            : nil
        return defaultTypingAttributes(blockKind: blockKind, listDepth: listDepth)
    }
}
